require 'active_support/concern'
require "action_view"
module Sprockets::Vue
  class CompileError < StandardError; end

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
            'blacklist' => ['useStrict'],
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
        name = input[:name].sub(/\.tpl$/, "")
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
              #{result['js']}; VComponents['#{j name}'] = module.exports;"
          end

          if template
            if compiler_path = Sprockets::Vue.template_compiler_path
              compiler_uri = input[:environment].resolve!(compiler_path).first
              source = input[:environment].load(compiler_uri).source
              if defined? Babel::Transpiler
                source << ';' << File.read(Babel::Transpiler.script_path)
                source << ";function compile(template) {
                  var result = VueTemplateCompiler.compile(template);
                  delete result['ast'];
                  if (result.errors && result.errors.length === 0) {
                    var self = this;
                    var babelOptions = { ast: false, blacklist: ['useStrict'], loose: ['es6.modules'] };
                    result.render = babel.transform(result.render, babelOptions).code;
                    result.staticRenderFns = result.staticRenderFns.map(function(fn) {
                      return babel.transform(fn, babelOptions).code
                    })
                  }
                  return result;
                }"
              else
                source << ";function compile(template) {
                  var result = VueTemplateCompiler.compile(template);
                  delete result['ast'];
                  return result;
                }"
              end
              context = ExecJS.compile(source)
              compiled = context.call('compile', template[:content])
              if compiled['errors'].empty?
                output << "VComponents['#{j name}'].render = function render() { #{compiled['render']} };"
                staticRenderFns = compiled['staticRenderFns'].map { |code|
                  "function() { #{code} }"
                }.join(',')
                output << "VComponents['#{j name}'].staticRenderFns = [#{staticRenderFns}];"
              else
                error = String.new
                error << "Error compiling template #{input[:filename]}:\n"
                error << template[:content]
                error << "\n"
                error << compiled['errors'].map { |e| "  - #{e}" }.join("\n")
                error << "\n"
                raise CompileError, error
              end
            else
              output << "VComponents['#{j name}'].template = '#{j template[:content]}';"
            end
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
