module Csvlint

  class CsvwColumn

    include Csvlint::ErrorCollector

    attr_reader :id, :about_url, :datatype, :default, :lang, :name, :null, :number, :ordered, :property_url, :required, :separator, :source_number, :suppress_output, :text_direction, :titles, :value_url, :virtual, :annotations

    def initialize(number, name, id: nil, about_url: nil, datatype: "xsd:string", default: "", lang: "und", null: [""], ordered: false, property_url: nil, required: false, separator: nil, source_number: nil, suppress_output: false, text_direction: :inherit, titles: {}, value_url: nil, virtual: false, annotations: [], warnings: [])
      @number = number
      @name = name
      @id = id
      @about_url = about_url
      @datatype = datatype
      @default = default
      @lang = lang
      @null = null
      @ordered = ordered
      @property_url = property_url
      @required = required
      @separator = separator
      @source_number = source_number || number
      @suppress_output = suppress_output
      @text_direction = text_direction
      @titles = titles
      @value_url = value_url
      @virtual = virtual
      @annotations = annotations
      reset
      @warnings += warnings
    end

    def validate_header(header)
      reset
      valid_headers = @titles ? @titles.map{ |l,v| v if CsvwColumn.languages_match(l, lang) }.flatten : []
      build_errors(:invalid_header, :schema, 1, @number, header, @titles) unless valid_headers.include? header
      return valid?
    end

    def validate(string_value, row=nil)
      reset
      value = parse(string_value || "", row)
      # STDERR.puts "#{name} - #{string_value.inspect} - #{value.inspect}"
      Array(value).each do |value|
        validate_required(value, row)
        validate_format(value, row)
        validate_length(value, row)
      end unless value.nil?
      validate_required(value, row) if value.nil?
      return valid?
    end

    def parse(string_value, row=nil)
      return nil if null.include? string_value

      value, warning = DATATYPE_PARSER[@datatype["base"] || @datatype["@id"]].call(string_value, @datatype["format"])
      return value if warning.nil?

      build_errors(warning, :schema, row, @number, string_value, @datatype)
      return string_value
    end

    def CsvwColumn.from_json(number, column_desc, base_url=nil, lang="und", inherited_properties={})
      annotations = {}
      warnings = []
      column_properties = {}
      inherited_properties = inherited_properties.clone

      column_desc.each do |property,value|
        if property == "@type"
          raise Csvlint::CsvwMetadataError.new("columns[#{number}].@type"), "@type of column is not 'Column'" if value != 'Column'
        else
          v, warning, type = CsvwPropertyChecker.check_property(property, value, base_url, lang)
          warnings += Array(warning).map{ |w| Csvlint::ErrorMessage.new(w, :metadata, nil, nil, "#{property}: #{value}", nil) } unless warning.nil? || warning.empty?
          if type == :annotation
            annotations[property] = v
          elsif type == :common || type == :column
            column_properties[property] = v
          elsif type == :inherited
            inherited_properties[property] = v
          else
            warnings << Csvlint::ErrorMessage.new(:invalid_property, :metadata, nil, nil, "column: #{property}", nil)
          end
        end
      end

      return CsvwColumn.new(number, column_properties["name"], 
        id: column_properties["@id"], 
        datatype: inherited_properties["datatype"] || { "@id" => "http://www.w3.org/2001/XMLSchema#string" }, 
        lang: inherited_properties["lang"] || "und",
        null: inherited_properties["null"] || [""],
        property_url: column_desc["propertyUrl"], 
        required: inherited_properties["required"] || false, 
        titles: column_properties["titles"], 
        virtual: column_properties["virtual"] || false,
        annotations: annotations, 
        warnings: warnings
      )
    end

    private
      def CsvwColumn.languages_match(l1, l2)
        return true if l1 == l2 || l1 == "und" || l2 == "und"
        return true if l1 =~ Regexp.new("^#{l2}-") || l2 =~ Regexp.new("^#{l1}-")
        return false
      end

      def validate_required(value, row)
        build_errors(:required, :schema, row, number, value, { "required" => @required }) if @required && value.nil?
      end

      def validate_length(value, row)
        if datatype["minLength"]
          build_errors(:min_length, :schema, row, number, value, { "minLength" => datatype["minLength"] }) if value.length < datatype["minLength"]
        end
      end

      def validate_format(value, row)
        if datatype["format"]
          build_errors(:format, :schema, row, number, value, { "format" => datatype["format"] }) unless DATATYPE_FORMAT_VALIDATION[datatype["base"]].call(value, datatype["format"])
        end
      end

      REGEXP_VALIDATION = lambda { |value, format| value =~ format }

      NO_ADDITIONAL_VALIDATION = lambda { |value, format| true }

      DATATYPE_FORMAT_VALIDATION = {
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" => REGEXP_VALIDATION,
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML" => REGEXP_VALIDATION,
        "http://www.w3.org/ns/csvw#JSON" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#anyAtomicType" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#anyURI" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#base64Binary" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#boolean" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#date" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dateTime" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dateTimeStamp" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#decimal" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#integer" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#long" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#int" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#short" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#byte" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#nonNegativeInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#positiveInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedLong" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedInt" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedShort" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#unsignedByte" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#nonPositiveInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#negativeInteger" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#double" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#duration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#dayTimeDuration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#yearMonthDuration" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#float" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gDay" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gMonth" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gMonthDay" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gYear" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#gYearMonth" => NO_ADDITIONAL_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#hexBinary" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#QName" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#string" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#normalizedString" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#token" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#language" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#Name" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#NMTOKEN" => REGEXP_VALIDATION,
        "http://www.w3.org/2001/XMLSchema#time" => NO_ADDITIONAL_VALIDATION
      }

      ALL_VALUES_VALID = lambda { |value, format| return value, nil }

      NUMERIC_PARSER = lambda { |value, format|
        format = Csvlint::CsvwNumberFormat.new() if format.nil?
        v = format.parse(value)
        return nil, :invalid_number if v.nil?
        return v, nil
      }

      DATATYPE_PARSER = {
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#XMLLiteral" => ALL_VALUES_VALID,
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#HTML" => ALL_VALUES_VALID,
        "http://www.w3.org/ns/csvw#JSON" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#anyAtomicType" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#anyURI" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#base64Binary" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#boolean" => lambda { |value, format|
          if format.nil?
            return true, nil if ["true", "1"].include? value
            return false, nil if ["false", "0"].include? value
          else
            return true, nil if value == format[0]
            return false, nil if value == format[1]
          end
          return value, :invalid_boolean
        },
        "http://www.w3.org/2001/XMLSchema#date" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#dateTime" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#dateTimeStamp" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#decimal" => lambda { |value, format|
          return nil, :invalid_decimal if value =~ /(E|^(NaN|INF|-INF)$)/
          return NUMERIC_PARSER.call(value, format)
        },
        "http://www.w3.org/2001/XMLSchema#integer" => lambda { |value, format|
          v, w = NUMERIC_PARSER.call(value, format)
          return v, :invalid_integer unless w.nil?
          return nil, :invalid_integer unless v.kind_of? Integer
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#long" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_long unless w.nil?
          return nil, :invalid_long unless v <= 9223372036854775807 && v >= -9223372036854775808
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#int" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_int unless w.nil?
          return nil, :invalid_int unless v <= 2147483647 && v >= -2147483648
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#short" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_short unless w.nil?
          return nil, :invalid_short unless v <= 32767 && v >= -32768
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#byte" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_byte unless w.nil?
          return nil, :invalid_byte unless v <= 127 && v >= -128
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#nonNegativeInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_nonNegativeInteger unless w.nil?
          return nil, :invalid_nonNegativeInteger unless v >= 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#positiveInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_positiveInteger unless w.nil?
          return nil, :invalid_positiveInteger unless v > 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedLong" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedLong unless w.nil?
          return nil, :invalid_unsignedLong unless v <= 18446744073709551615
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedInt" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedInt unless w.nil?
          return nil, :invalid_unsignedInt unless v <= 4294967295
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedShort" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedShort unless w.nil?
          return nil, :invalid_unsignedShort unless v <= 65535
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#unsignedByte" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#nonNegativeInteger"].call(value, format)
          return v, :invalid_unsignedByte unless w.nil?
          return nil, :invalid_unsignedByte unless v <= 255
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#nonPositiveInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_nonPositiveInteger unless w.nil?
          return nil, :invalid_nonPositiveInteger unless v <= 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#negativeInteger" => lambda { |value, format|
          v, w = DATATYPE_PARSER["http://www.w3.org/2001/XMLSchema#integer"].call(value, format)
          return v, :invalid_negativeInteger unless w.nil?
          return nil, :invalid_negativeInteger unless v < 0
          return v, w
        },
        "http://www.w3.org/2001/XMLSchema#double" => NUMERIC_PARSER,
        "http://www.w3.org/2001/XMLSchema#duration" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#dayTimeDuration" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#yearMonthDuration" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#float" => NUMERIC_PARSER,
        "http://www.w3.org/2001/XMLSchema#gDay" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#gMonth" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#gMonthDay" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#gYear" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#gYearMonth" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#hexBinary" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#QName" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#string" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#normalizedString" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#token" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#language" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#Name" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#NMTOKEN" => ALL_VALUES_VALID,
        "http://www.w3.org/2001/XMLSchema#time" => ALL_VALUES_VALID
      }

  end
end
