module Sprockets::Vue
  class Style
    class << self
      STYLE_REGEX = Utils.node_regex('style')
      STYLE_COMPILES = {
        'scss' => Sprockets::ScsscProcessor,
        'sass' => Sprockets::SasscProcessor,
        nil => ->(i){i[:data]}
      }
      def call(input)
        data = input[:data]
        input[:cache].fetch([cache_key, input[:filename], data]) do
          style = STYLE_REGEX.match(data)
          if style
            input[:data] = style[:content]
            STYLE_COMPILES[style[:lang]].call(input)
          else
            ''
          end
        end
      end

      def cache_key
        [
          self.name,
          VERSION,
        ].freeze
      end
    end
  end
end
