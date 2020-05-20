module Condenser::ParseHelpers

  attr_accessor :matched

  def eos?
    @index >= @source.size
  end

  def scan_until(r)
    index = @source.index(r, @index)
    match = @source.match(r, @index)
    if match
      @matched = match.to_s
      @old_index = @index
      @index = index + @matched.size
    else
      @matched = nil
    end
    match
  end

  def pre_match
    @source[@old_index...(@index-@matched.size)]
  end

  def rewind(by=1)
    @index -= by
  end

  def forward(by=1)
    @index += by
  end

  def seek(pos)
    @old_index = nil
    @matched = nil
    @index = pos
  end

  def next_word
    nw = @source.match(/\s*(\S+)/, @index)
    nw.nil? ? nil : nw[1]
  end

  def current_line
    start = (@source.rindex(/(\n|\z)/, @old_index) || 0) + 1
    uptop = @source.index(/(\n|\z)/, @index) || (@old_index + @matched.length)
    @source[start..uptop]
  end

  def cursor
    start = (@source.rindex("\n", @old_index) || 0) + 1
    uptop = @source.index("\n", @index) || (@old_index + @matched.length)
    lineno = @source[0..start].count("\n") + 1
    "#{lineno.to_s.rjust(4)}: " + @source[start..uptop] + "\n      #{'-'* (@old_index+1-start)}#{'^'*(@matched.length)}"
  end

end