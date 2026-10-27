# frozen_string_literal: true

require 'json'
require 'set'

# Compiles stylesheets that `@import "tailwindcss"` or use `@reference` with
# Tailwind CSS v4, in a node process that's kept running between builds.
# Other stylesheets are left as they are. It's registered as an instance:
#
#     register_preprocessor 'text/css', Condenser::TailwindProcessor.new(npm_path)
#
# Tailwind's automatic source detection scans the environment's base, like
# the Tailwind CLI from its working directory, or only the +sources:+ if
# they're given. Every file Tailwind scans for class names, and every
# directory it scans, is recorded as a file or directory dependency, except
# gitignored directories found by automatic source detection. The
# +sources:+ are watched, so a change there rebuilds the CSS in a running
# process; the environment's base isn't.
class Condenser::TailwindProcessor < Condenser::Processor

  SCRIPT = File.expand_path('tailwind_processor.js', __dir__)
  PACKAGES = %w[tailwindcss @tailwindcss/node @tailwindcss/oxide ignore].freeze
  IMPORT = /@import\s+(?:url\(\s*)?["']tailwindcss["'\/]|@reference\b/

  # Whether it minifies, the sources: as given, and the versions of the
  # Tailwind packages and `ignore`, which are part of the pipeline digest.
  attr_reader :options

  # npm_path  - The directory Tailwind's packages are installed into, with
  #              `npm`, if they aren't there.
  # sources:   - The directories to scan instead of the environment's base,
  #              like `source(none)` and an `@source` for each, relative to
  #              the environment's base or absolute, such as `app`, `lib/` or
  #              a gem's `app/views`. They're watched and have to exist. A
  #              `source(...)` on the stylesheet's import replaces the
  #              environment's base, and the sources are still scanned.
  #              Without them, and without an environment base, a stylesheet
  #              needs `source(...)` or `source(none)`.
  # minify:    - Minify the CSS like `tailwindcss --minify`. Default false.
  # max_memory - The node process is restarted after a build that leaves it
  #              using more than this many bytes.
  def initialize(npm_path, sources: [], minify: false, max_memory: Condenser::NodeWorker::MAX_MEMORY)
    node = Condenser::NodeProcessor.new(npm_path)
    node.npm_install(PACKAGES)
    @binary = node.binary
    @modules = node.npm_module_path
    @sources = Array(sources).map(&:to_s)
    @minify = minify
    @max_memory = max_memory
    @lock = Mutex.new
    @unwatched = Set.new
    @options = { minify: minify, sources: @sources }
    PACKAGES.each do |package|
      @options[package.to_sym] = JSON.parse(File.read(File.join(@modules, package, 'package.json')))['version']
    end
  end

  # Watches the sources, before an asset's cached dependencies are resolved,
  # so it's done when the CSS isn't rebuilt. The environment's base isn't
  # watched, since it has `tmp/`, `public/assets` and the like in it.
  def setup(environment)
    super
    resolve(environment).each { |dir| environment.watch(dir) }
  end

  def call(environment, input)
    return if !input[:source].match?(IMPORT)

    result = build(environment, input)
    input[:source] = result['css']
    record_dependencies(environment, input, result)
    input
  end

  private

  def worker
    @lock.synchronize do
      @worker ||= Condenser::NodeWorker.new(@binary, @modules, script: SCRIPT, name: 'tailwind', max_memory: @max_memory)
    end
  end

  # The sources, as absolute paths.
  def resolve(environment)
    root = environment.base&.to_s
    @sources.map do |source|
      if root.nil? && !source.start_with?('/')
        raise Condenser::Error, "TailwindProcessor source #{source} is relative, which needs the environment's base"
      end

      path = File.expand_path(source, root)
      raise Condenser::Error, "TailwindProcessor source #{source} isn't a directory (#{path})" if !File.directory?(path)

      path
    end
  end

  def build(environment, input)
    config = { file: input[:source_file], css: input[:source].dup.force_encoding(Encoding::UTF_8), base: environment.base&.to_s, sources: resolve(environment), minify: @minify }
    attempts = 0
    message = begin
      worker.build(config, logger: environment.logger)
    rescue Condenser::NodeWorker::WorkerDied
      retry if (attempts += 1) == 1 && !worker.stopping?
      raise
    end
    raise Condenser::Error, "#{input[:filename]}: #{message['args'][1]}" if message['method'] == 'error'

    message['args'][0]
  end

  # The scanned files are file dependencies, and the directories Tailwind
  # reports globs for are directory dependencies, so a matching file added
  # to them rebuilds the CSS. A directory with scanned files that no glob
  # covers depends on all its names, and one that's missing on the names of
  # the subdirectories of its nearest parent.
  def record_dependencies(environment, input, result)
    input[:file_dependencies].merge((result['dependencies'] + result['files']).uniq - [input[:source_file]])

    directories = result['globs'].map do |glob|
      { path: glob['base'], glob: File.basename(glob['pattern']), recursive: glob['pattern'].include?('/') }
    end
    covered = directories.to_set { |d| d[:path] }
    recursive = directories.select { |d| d[:recursive] }.to_set { |d| File.join(d[:path], '') }
    result['files'].map { |f| File.dirname(f) }.uniq.each do |dir|
      next if covered.include?(dir) || ancestors(dir).any? { |a| recursive.include?(File.join(a, '')) }

      directories << { path: dir }
    end
    directories.each do |d|
      next if File.directory?(d[:path])

      d[:path] = File.dirname(d[:path]) until File.directory?(d[:path])
      d[:glob] = []
      d[:recursive] = false
    end
    input[:directory_dependencies].merge(directories)
    warn_unwatched(environment, directories.map { |d| d[:path] })
  end

  # The directories above +dir+, nearest first.
  def ancestors(dir)
    dirs = []
    dirs << dir until dir == (dir = File.dirname(dir))
    dirs
  end

  # The listener only notices changes under the load paths and the watched
  # paths.
  def warn_unwatched(environment, directories)
    return if !environment.build_cache.listening

    roots = environment.path.map { |p| [Condenser::BuildCache.real_path(p), nil] } +
      environment.watched_paths.map { |p, ignore| [Condenser::BuildCache.real_path(p), ignore] }
    directories.each do |dir|
      real = Condenser::BuildCache.real_path(dir)
      next if roots.any? { |root, ignore| Condenser::BuildCache.covers?(root, real, ignore: ignore) }
      next if !@unwatched.add?(real)

      environment.logger.warn("Tailwind scans #{dir}, which isn't watched, so changes there won't rebuild the CSS until the process restarts; see env.watch")
    end
  end
end
