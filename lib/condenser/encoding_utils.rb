class Condenser
  module EncodingUtils

    # Internal: Mapping unicode encodings to byte order markers.
    BOM = {
      ::Encoding::UTF_32LE => [0xFF, 0xFE, 0x00, 0x00],
      ::Encoding::UTF_32BE => [0x00, 0x00, 0xFE, 0xFF],
      ::Encoding::UTF_8    => [0xEF, 0xBB, 0xBF],
      ::Encoding::UTF_16LE => [0xFF, 0xFE],
      ::Encoding::UTF_16BE => [0xFE, 0xFF]
    }
    
    # Public: Basic string detecter.
    #
    # Attempts to parse any Unicode BOM otherwise falls back to the
    # environment's external encoding.
    #
    # str - ASCII-8BIT encoded String
    #
    # Returns encoded String.
    def detect(str)
      str = detect_unicode_bom(str)

      # Fallback to environment's external encoding
      if str.encoding == Encoding::BINARY
        str.force_encoding(Encoding.default_external)
      end

      str
    end

    # Public: Detect Unicode string.
    #
    # Attempts to parse Unicode BOM and falls back to UTF-8.
    #
    # str - ASCII-8BIT encoded String
    #
    # Returns encoded String.
    def detect_unicode(str)
      str = detect_unicode_bom(str)

      # Fallback to UTF-8
      if str.encoding == Encoding::BINARY
        str.force_encoding(Encoding::UTF_8)
      end

      str
    end

    # Public: Detect and strip BOM from possible unicode string.
    #
    # str - ASCII-8BIT encoded String
    #
    # Returns UTF 8/16/32 encoded String without BOM or the original String if
    # no BOM was present.
    def detect_unicode_bom(str)
      bom_bytes = str.byteslice(0, 4).bytes.to_a

      BOM.each do |encoding, bytes|
        if bom_bytes[0, bytes.size] == bytes
          str = str.dup
          str.force_encoding(Encoding::BINARY)
          str.slice!(0, bytes.size)
          str.force_encoding(encoding)
          return str
        end
      end

      return str
    end

    # Public: Detect and strip @charset from CSS style sheet.
    #
    # str - String.
    #
    # Returns a encoded String.
    def detect_css(str)
      str = detect_unicode_bom(str)

      if name = scan_css_charset(str)
        encoding = Encoding.find(name)
        str = str.dup
        str.force_encoding(encoding)
        len = "@charset \"#{name}\";".encode(encoding).size
        str.slice!(0, len)
        str
      end

      # Fallback to UTF-8
      if str.encoding == Encoding::BINARY
        str.force_encoding(Encoding::UTF_8)
      end

      str
    end

    # Internal: @charset bytes
    CHARSET_START = [0x40, 0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74, 0x20, 0x22]
    CHARSET_SIZE  = CHARSET_START.size

    # Internal: Scan binary CSS string for @charset encoding name.
    #
    # str - ASCII-8BIT encoded String
    #
    # Returns encoding String name or nil.
    def scan_css_charset(str)
      buf = []
      i = 0

      str.each_byte.each do |byte|
        # Halt on line breaks
        break if byte == 0x0A || byte == 0x0D

        # Only ascii bytes
        next unless 0x0 < byte && byte <= 0xFF

        if i < CHARSET_SIZE
        elsif i == CHARSET_SIZE
          if buf == CHARSET_START
            buf = []
          else
            break
          end
        elsif byte == 0x22
          return buf.pack('C*')
        end

        buf << byte
        i += 1
      end

      nil
    end
    
    # Public: Detect charset from HTML document.
    #
    # Attempts to parse any Unicode BOM otherwise attempt Charlock detection
    # and finally falls back to the environment's external encoding.
    #
    # str - String.
    #
    # Returns a encoded String.
    def detect_html(str)
      str = detect_unicode_bom(str)

      # Fallback to environment's external encoding
      if str.encoding == Encoding::BINARY
        str.force_encoding(Encoding.default_external)
      end

      str
    end
    
  end
end