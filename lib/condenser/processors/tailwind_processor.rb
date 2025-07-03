# frozen_string_literal: true

class Condenser::TailwindProcessor < Condenser::NodeProcessor
  attr :options

  def self.setup(environment)
    require "tailwindcss/ruby" unless defined?(::Tailwindcss::Ruby)
  end

  def call(environment, input)
    Tempfile.open(['out', 'css']) do |outfile|
      system('tailwindcss', '-i', input[:source_file], '-o', outfile.path)
      input[:source] = outfile.read
    end
  end
end
