require "nokogiri"
require 'fiber'

module SAXMachine
  
  def self.included(base)
    base.extend ClassMethods
  end
  
  def parse(thing)
    @parser = Fiber.new do 
      Nokogiri::XML::SAX::Parser.new( SAXHandler.new(self) ).parse(thing)
    end
    @use_this_value = @parser.resume
    self
  end
  
  module ClassMethods

    def parse(xml_text)
      new.parse(xml_text)
    end
    
    def element(name, options = {})
      options[:as] ||= name
      sax_config.add_top_level_element(name, options)
      __add_accessors__  options
    end

    def attribute(name, options = {})
      options[:as] ||= name
      sax_config.add_top_level_attribute(self.class.to_s, options.merge(:name => name))
      __add_accessors__  options
    end

    def value(name, options = {})
      options[:as] ||= name
      sax_config.add_top_level_element_value(self.class.to_s, options.merge(:name => name))
      __add_accessors__  options
    end

    # we only want to insert the getter and setter if they haven't defined it from elsewhere.
    # this is how we allow custom parsing behavior. So you could define the setter
    # and have it parse the string into a date or whatever.
    def __add_accessors__ options
      attr_reader options[:as] unless instance_methods.include?(options[:as].to_sym)
      attr_writer options[:as] unless instance_methods.include?("#{options[:as]}=".to_sym)
    end

    def columns
      sax_config.columns
    end

    def column(sym)
      columns.select{|c| c.column == sym}[0]
    end

    def data_class(sym)
      column(sym).data_class
    end

    def required?(sym)
      column(sym).required?
    end

    def column_names
      columns.map{|e| e.column}
    end
    
    def elements(name, options = {})
      options[:as] ||= name
      if options[:class]
        sax_config.add_collection_element(name, options)
      else
        unless options[:lazy]
          class_eval <<-SRC
            def add_#{options[:as]}(value)
              #{options[:as]} << value
            end
          SRC
        else
          class_eval <<-SRC
            def add_#{options[:as]}(value)
              Fiber.yield value
            end
          SRC
        end
        sax_config.add_top_level_element(name, options.merge(:collection => true))
      end
      
      unless options[:lazy]
        class_eval <<-SRC if !instance_methods.include?(options[:as].to_s)
          def #{options[:as]} value = nil
            if value
              #{options[:as]} << value
              return
            end
            @#{options[:as]} ||= []
          end
        SRC
      else
        class_eval <<-SRC 
          def #{options[:as]} value = nil
            return Fiber.yield value if value
            @#{options[:as]} ||= Enumerator.new do |yielderr|
              if @use_this_value
                yielderr << @use_this_value
                @use_this_value = nil
              end
              while r = @parser.resume
                yielderr << r
              end
            end
          end
        SRC
      end
      
      attr_writer options[:as] unless instance_methods.include?("#{options[:as]}=".to_sym)
    end
    
    def sax_config
      @sax_config ||= SAXConfig.new
    end
  end
  
end
