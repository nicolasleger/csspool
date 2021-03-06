module CSSPool
  module Visitors
    class ToCSS < Visitor

      CSS_IDENTIFIER_ILLEGAL_CHARACTERS =
        (0..255).to_a.pack('U*').gsub(/[a-zA-Z0-9_-]/, '')
      CSS_STRING_ESCAPE_MAP = {
        "\\" => "\\\\",
        "\"" => "\\\"",
        "\n" => "\\a ", # CSS2 4.1.3 p3.2
        "\r" => "\\\r",
        "\f" => "\\\f"
      }

      def initialize
        @indent_level = 0
        @indent_space = indent_space
      end

      visitor_for CSS::Document do |target|
        # FIXME - this does not handle nested parent rules, like
        # @document domain(example.com) {
        #   @media screen {
        #     a { color: blue; }
        #   }
        # }
        current_parent_rule = []

        tokens = []

        target.charsets.each do |char_set|
          tokens << char_set.accept(self)
        end

        target.import_rules.each do |ir|
          tokens << ir.accept(self)
        end

        target.fontface_rules.each do |ffr|
          tokens << ffr.accept(self)
        end

        target.rule_sets.each { |rs|
          # FIXME - handle other kinds of parents
          if !rs.parent_rule.nil? and rs.parent_rule != current_parent_rule
            media = rs.parent_rule
            tokens << "#{indent}@media #{media} {"
            @indent_level += 1
          end

          tokens << rs.accept(self)

          if rs.parent_rule != current_parent_rule
            current_parent_rule = rs.parent_rule
            if !rs.parent_rule.nil?
              @indent_level -= 1
              tokens << "#{indent}}"
            end
          end
        }
        tokens.join(line_break)
      end

      visitor_for CSS::MediaType do |target|
        escape_css_identifier(target.name)
      end

      visitor_for CSS::MediaFeature do |target|
        "(#{escape_css_identifier(target.property)}:#{target.value})"
      end

      visitor_for CSS::MediaQuery do |target|
        ret = ''
        if target.only_or_not
          ret << target.only_or_not.to_s + ' '
        end
        ret << target.media_expr.accept(self)
        if target.and_exprs.any?
          ret << ' and '
        end
        ret << target.and_exprs.map { |expr| expr.accept(self) }.join(' and ')
      end

      visitor_for CSS::MediaQueryList do |target|
        target.media_queries.map do |m|
          m.accept(self)
        end.join(', ')
      end

      visitor_for CSS::Charset do |target|
        "@charset \"#{escape_css_string target.name}\";"
      end

      visitor_for CSS::FontfaceRule do |target|
        "@font-face {#{line_break}" +
        "#{indent}" +
          target.declarations.map { |decl| decl.accept self }.join(line_break) +
          "#{line_break}#{indent}}"
      end

      visitor_for CSS::ImportRule do |target|
        media = ''
        media = " " + target.media_list.map do |medium|
          escape_css_identifier medium.name
        end.join(', ') if target.media_list.length > 0

        "#{indent}@import #{target.uri.accept(self)}#{media};"
      end

      visitor_for CSS::DocumentQuery do |target|
        "#{indent}@document #{target.url_functions.join(', ')} {}"
      end

      visitor_for CSS::NamespaceRule do |target|
        if target.prefix.nil?
          "#{indent}@namespace #{target.uri.accept(self)}"
        else
          "#{indent}@namespace #{target.prefix.value} #{target.uri.accept(self)}"
        end
      end

      visitor_for CSS::RuleSet do |target|
        if target.selectors.any?
          "#{indent}" +
            target.selectors.map { |sel| sel.accept self }.join(", ") + " {#{line_break}" +
            target.declarations.map { |decl| decl.accept self }.join(line_break) +
            "#{line_break}#{indent}}"
        else
          ''
        end
      end

      visitor_for CSS::Declaration do |target|
        important = target.important? ? ' !important' : ''

        # only output indents and semicolons if this is in a ruleset
        indent {
          "#{target.rule_set.nil? ? '' : indent}#{escape_css_identifier target.property}: " + target.expressions.map { |exp|

            op = '/' == exp.operator ? ' /' : exp.operator

            [
              op,
              exp.accept(self),
            ].join ' '
          }.join.strip + important + (target.rule_set.nil? ? '' : ';')
        }
      end

      visitor_for Terms::Ident do |target|
        escape_css_identifier target.value
      end

      visitor_for Terms::Hash do |target|
        "##{target.value}"
      end

      visitor_for Terms::URI do |target|
        "url(\"#{escape_css_string target.value}\")"
      end

      visitor_for Terms::Function do |target|
        "#{escape_css_identifier target.name}(" +
          target.params.map { |x|
            x.is_a?(String) ? x : [
              x.operator,
              x.accept(self)
            ].compact.join(' ')
          }.join + ')'
      end

      visitor_for Terms::Rgb do |target|
        params = [
          target.red,
          target.green,
          target.blue
        ].map { |c|
          c.accept(self)
        }.join ', '

        %{rgb(#{params})}
      end

      visitor_for Terms::String do |target|
        "\"#{escape_css_string target.value}\""
      end

      visitor_for Terms::Number do |target|
        [
          target.unary_operator == :minus ? '-' : nil,
          target.value,
          target.type
        ].compact.join
      end

      visitor_for Terms::Resolution do |target|
        "#{target.number}#{target.unit}"
      end

      visitor_for Selector do |target|
        target.simple_selectors.map { |ss| ss.accept self }.join
      end

      visitor_for Selectors::Simple, Selectors::Universal, Selectors::Type do |target|
        combo = {
          :s => ' ',
          :+ => ' + ',
          :> => ' > ',
          :~ => ' ~ '
        }[target.combinator]

        name = [nil, '*'].include?(target.name) ? target.name : escape_css_identifier(target.name)
        [combo, name].compact.join +
          target.additional_selectors.map { |as| as.accept self }.join
      end

      visitor_for Selectors::Id do |target|
        "##{escape_css_identifier target.name}"
      end

      visitor_for Selectors::Class do |target|
        ".#{escape_css_identifier target.name}"
      end

      visitor_for Selectors::PseudoClass do |target|
        if target.extra.nil?
          ":#{escape_css_identifier target.name}"
        else
          ":#{escape_css_identifier target.name}(#{escape_css_identifier target.extra})"
        end
      end

      visitor_for Selectors::PseudoElement do |target|
        if target.css2.nil?
          "::#{escape_css_identifier target.name}"
        else
          ":#{escape_css_identifier target.name}"
        end
      end

      visitor_for Selectors::Attribute do |target|
        case target.match_way
        when Selectors::Attribute::SET
          "[#{escape_css_identifier target.name}]"
        when Selectors::Attribute::EQUALS
          "[#{escape_css_identifier target.name}=\"#{escape_css_string target.value}\"]"
        when Selectors::Attribute::INCLUDES
          "[#{escape_css_identifier target.name} ~= \"#{escape_css_string target.value}\"]"
        when Selectors::Attribute::DASHMATCH
          "[#{escape_css_identifier target.name} |= \"#{escape_css_string target.value}\"]"
        when Selectors::Attribute::PREFIXMATCH
          "[#{escape_css_identifier target.name} ^= \"#{escape_css_string target.value}\"]"
        when Selectors::Attribute::SUFFIXMATCH
          "[#{escape_css_identifier target.name} $= \"#{escape_css_string target.value}\"]"
        when Selectors::Attribute::SUBSTRINGMATCH
          "[#{escape_css_identifier target.name} *= \"#{escape_css_string target.value}\"]"
        else
          raise "no matching matchway"
        end
      end

      private
      def indent
        if block_given?
          @indent_level += 1
          result = yield
          @indent_level -= 1
          return result
        end
        "#{@indent_space * @indent_level}"
      end

      def line_break
        "\n"
      end

      def indent_space
        '  '
      end

      def escape_css_identifier text
        # CSS2 4.1.3 p2
        unsafe_chars = /[#{Regexp.escape CSS_IDENTIFIER_ILLEGAL_CHARACTERS}]/
        text.gsub(/^\d|^\-(?=\-|\d)|#{unsafe_chars}/um) do |char|
          if ':()-\\ ='.include? char
            "\\#{char}"
          else # I don't trust others to handle space termination well.
            "\\#{char.unpack('U').first.to_s(16).rjust(6, '0')}"
          end
        end
      end

      def escape_css_string text
        text.gsub(/[\\"\n\r\f]/) {CSS_STRING_ESCAPE_MAP[$&]}
      end
    end

    class ToMinifiedCSS < ToCSS
      def line_break
        ""
      end

      def indent_space
        ' '
      end

      visitor_for CSS::RuleSet do |target|
          target.selectors.map { |sel| sel.accept self }.join(", ") + " {" +
          target.declarations.map { |decl| decl.accept self }.join +
          " }"
      end
    end
  end
end
