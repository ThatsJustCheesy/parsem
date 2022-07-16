require "../spec_helper"
require "json"
include Parsem

STRING_DELIMETER       = '"'
STRING_ESCAPE_CHAR     = '\\'
ARRAY_START_DELIMITER  = '['
ARRAY_END_DELIMITER    = ']'
OBJECT_START_DELIMITER = '{'
OBJECT_END_DELIMITER   = '}'
ITEM_DELIMITER         = ','
KEY_VALUE_DELIMITER    = ':'

alias JSONValue = JSON::Any
value = Parser(Char, JSONValue).fail

null = (
  string("null")
).map { JSONValue.new(nil) }

bool = (
  string("true") | string("false")
).map { |s| JSONValue.new(s[0] == 't') }

integer = (
  Parsem.digit.repeat(1..)
).join.map { |s| JSONValue.new(s.to_i64) }.name("integer")

string_content_char_simple = none_of([STRING_DELIMETER, STRING_ESCAPE_CHAR])
string_content_char_escape_seq = \
   (token(STRING_ESCAPE_CHAR) >> alternatives(
    [{'"', '"'},
     {'\\', '\\'},
     {'/', '/'},
     {'b', '\b'},
     {'f', '\f'},
     {'n', '\n'},
     {'r', '\r'},
     {'t', '\t'},
    ]
      .map { |char| token(char[0]).map { char[1] } }
  ))
string_content_char = string_content_char_simple | string_content_char_escape_seq

string_raw = (
  token(STRING_DELIMETER) >>
  string_content_char.repeat(0..) <<
  token(STRING_DELIMETER)
).join
string = string_raw.map { |s| JSONValue.new(s) }.name("string")

array = (
  token(ARRAY_START_DELIMITER) >> ws >>
  lazy(
    ((value << ws << token(ITEM_DELIMITER) << ws).repeat(..).extend <=>
     value).optional.flatten
  ) <<
  ws << token(ARRAY_END_DELIMITER)
).map { |array| JSONValue.new(array) }.name("array")

record KeyValuePair, key : String, value : JSONValue
object_key_value_pair = infer(->KeyValuePair.new) ^
                        string_raw.name("key") << ws << token(KEY_VALUE_DELIMITER) << ws <=>
                        lazy(value)

object = (
  token(OBJECT_START_DELIMITER) >> ws >>
  (((object_key_value_pair << ws << token(ITEM_DELIMITER) << ws).repeat(..).extend <=>
    object_key_value_pair)).optional.flatten <<
  ws << token(OBJECT_END_DELIMITER)
).map { |key_value_pairs| JSONValue.new Hash.zip(
  key_value_pairs.map &.key,
  key_value_pairs.map &.value
) }.name("object")

value = null | bool | integer | string | array | object
json = ws >> (array | object) << ws

# TODO: Tests for arrays
describe "JSON parser" do
  context "given valid input" do
    it "parses empty objects" do
      json.parse(
        <<-'END'
          {}
        END
      ).should eq({} of JSONValue => JSONValue)
      json.parse(
        <<-'END'
          {  }
        END
      ).should eq({} of JSONValue => JSONValue)
    end

    it "parses objects with simple key-value pairs" do
      json.parse(
        <<-'END'
          {"a": "b"}
        END
      ).should eq({"a" => "b"})
      json.parse(
        <<-'END'
          {
            "abc": 123,
            "defg": null,
            "h": true,
            "i": false,
            "j": [],
            "k": {}
          }
        END
      ).should eq({
        "abc"  => 123,
        "defg" => nil,
        "h"    => true,
        "i"    => false,
        "j"    => [] of JSONValue,
        "k"    => {} of JSONValue => JSONValue,
      })
    end

    it "parses objects with keys that contain escape sequences" do
      json.parse(
        <<-'END'
          {"quote\"backslash\\tab\tlinebreak\n": "value"}
        END
      ).should eq({"quote\"backslash\\tab\tlinebreak\n" => "value"})
    end

    # it "doesn't take forever" do
    #   json.parse(
    #     "[#{(1..100000).to_a.join(", ")}]"
    #   )
    # end
  end

  context "given invalid input" do
    it "rejects unclosed objects" do
      json.parse(
        <<-'END'
          {
        END
      ).to_s.should eq("ParseError: expected }, but found end of input")

      json.parse(
        <<-'END'
          {
            "abc": "defg"
        END
      ).to_s.should eq("ParseError: expected }, but found end of input")
    end

    it "rejects objects with trailing commas" do
      json.parse(
        <<-'END'
          {,}
        END
      ).to_s.should eq("ParseError: expected }, but found ,")
      json.parse(
        <<-'END'
          {"a": "b", }
        END
      ).to_s.should eq("ParseError: expected key, but found }")
    end

    it "rejects objects without keys for values" do
      json.parse(
        <<-'END'
          { : "value" }
        END
      ).to_s.should eq("ParseError: expected }, but found :")
    end

    it "rejects objects without values for keys" do
      json.parse(
        <<-'END'
          {"key": }
        END
      ).to_s.should eq("ParseError: expected null, true, false, integer, string, array or object, but found }")
      json.parse(
        <<-'END'
          {
            "a": "b",
            "c": "d",
            "e"
          }
        END
      ).to_s.should eq("ParseError: expected :, but found }")
    end
  end
end
