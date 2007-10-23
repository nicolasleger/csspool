module CSS
  module SAC
    class Selector
      attr_reader :selector_type
    end

    class SimpleSelector < Selector
      def initialize
        @selector_type = :SAC_ANY_NODE_SELECTOR
      end
    end

    class ElementSelector < SimpleSelector
      attr_reader :local_name
      alias :name :local_name

      def initialize(name)
        super()
        @selector_type = :SAC_ELEMENT_NODE_SELECTOR
        @local_name = name
      end
    end

    class ConditionalSelector < SimpleSelector
      attr_accessor :condition, :simple_selector
      alias :selector :simple_selector

      def initialize(selector, condition)
        @condition  = condition
        @selector   = selector
      end
    end
  end
end
