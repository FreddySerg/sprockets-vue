require 'active_support/concern'
require "action_view"
module Sprockets::Vue
  class Script
    class << self
      include ActionView::Helpers::JavaScriptHelper

      SCRIPT_REGEX = Utils.node_regex('script')
      TEMPLATE_REGEX = Utils.node_regex('template')
      SCRIPT_COMPILES = {
        'coffee' => ->(s, input){
          CoffeeScript.compile(s, sourceMap: true, sourceFiles: [input[:source_path]], no_wrap: true)
        },
        'javascript' => ->(s, input){
          return { 'js' => s } unless defined? Babel::Transpiler

          result = Babel::Transpiler.transform(s, {
            'sourceRoot' => input[:load_path],
            'moduleRoot' => nil,
            'filename' => input[:filename],
            'filenameRelative' => input[:environment].split_subpath(input[:load_path], input[:filename])
          })

          { 'js' => result['code'] }
        }
      }
      def call(input)
        data = input[:data]
        name = input[:name]
        input[:cache].fetch([cache_key, input[:source_path], data]) do
          script = SCRIPT_REGEX.match(data)
          template = TEMPLATE_REGEX.match(data)
          output = []
          map = nil
          if script
            lang = script[:lang] || 'javascript'
            if lang == 'es6' and defined? Babel::Transpiler
              lang = 'javascript'
            end
            unless SCRIPT_COMPILES.key? lang
              fail "Unsupported Sprockets::Vue script lang attribute #{script[:lang].inspect}"
            end
            result = SCRIPT_COMPILES[lang].call(script[:content], input)

            map = result['sourceMap']

            output << "'object' != typeof VComponents && (this.VComponents = {});
              var module = { exports: null }, exports = {};
              #{result['js']}; VComponents['#{name}'] = module.exports;"
          end

          if template
            output << "VComponents['#{name.sub(/\.tpl$/, "")}'].template = '#{j template[:content]}';"
          end

          { data: "#{warp(output.join)}", map: map }
        end
      end

      def warp(s)
        "(function(){#{s}}).call(this);"
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
