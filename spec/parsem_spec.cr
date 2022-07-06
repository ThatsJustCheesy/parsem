require "./spec_helper"

require "./json_parser"

include Parsem

describe Parsem do
  describe Parser do
    describe "#parse" do
      it "fails if the entire input is not consumed" do
        Parser(Int32, Int32).pure(123).parse([1]).should be_a(ParseError(Int32))
        Parser(Char, String).pure("hello").parse("lalala").should be_a(ParseError(Char))
      end
    end

    describe ".pure" do
      it "matches nothing and returns its argument" do
        Parser(Int32, Int32).pure(123).parse([] of Int32).should eq(123)
        Parser(Char, String).pure("hello").parse("").should eq("hello")
      end
    end

    describe ".fail" do
      it "fails unconditionally" do
        Parser(Int32, Int32).fail.parse([] of Int32).should be_a(ParseError(Int32))
        Parser(Char, String).fail.parse("").should be_a(ParseError(Char))
        Parser(Char, String).fail.parse("abc").should be_a(ParseError(Char))
      end
    end
  end

  describe ".token" do
    it "matches its argument" do
      token('a').parse("a").should eq('a')
      token(123).parse([123]).should eq(123)
    end

    it "doesn't match anything else" do
      token('a').parse("b").should be_a(ParseError(Char))
      token(123).parse([456]).should be_a(ParseError(Int32))
    end
  end

  describe ".not" do
    it "doesn't match its argument" do
      not('a').parse("a").should be_a(ParseError(Char))
      not(123).parse([123]).should be_a(ParseError(Int32))
    end

    it "matches anything else" do
      not('a').parse("b").should eq('b')
      not(123).parse([456]).should eq(456)
    end
  end

  describe ".one_of" do
    it "matches one of its arguments" do
      one_of(['a', 'b']).parse("a").should eq('a')
      one_of(['a', 'b']).parse("b").should eq('b')
    end

    it "doesn't match a token that was not in its arguments" do
      one_of([] of Char).parse("a").should be_a(ParseError(Char))
      one_of(['a', 'b']).parse("c").should be_a(ParseError(Char))
    end

    it "matches exactly one token" do
      one_of(['a', 'b']).parse("").should be_a(ParseError(Char))
      one_of(['a', 'b']).parse("ab").should be_a(ParseError(Char))
      one_of(['a', 'b']).parse("aa").should be_a(ParseError(Char))
    end
  end

  describe ".none_of" do
    it "doesn't match any of its arguments" do
      none_of(['a', 'b']).parse("a").should be_a(ParseError(Char))
      none_of(['a', 'b']).parse("b").should be_a(ParseError(Char))
    end

    it "matches any token that was not in its arguments" do
      none_of([] of Char).parse("a").should eq('a')
      none_of(['a', 'b']).parse("c").should eq('c')
    end

    it "matches exactly one token" do
      none_of(['a', 'b']).parse("").should be_a(ParseError(Char))
      none_of(['a', 'b']).parse("cc").should be_a(ParseError(Char))
    end
  end

  describe ".string" do
    it "matches the characters in its argument, in order" do
      string("").parse("").should eq("")
      string("hello").parse("hello").should eq("hello")
    end

    it "doesn't match anything else" do
      string("").parse("hello").should be_a(ParseError(Char))
      string("hello").parse("").should be_a(ParseError(Char))
      string("hello").parse("helloo").should be_a(ParseError(Char))
    end
  end

  describe Parser do
    describe "#|" do
      it "applies the left parser and returns its result if it succeeds" do
        parser = Parser(Char, String).pure("left") |
                 Parser(Char, String).pure("right")
        parser.parse("").should eq("left")
      end

      it "applies the right parser and returns its result if the left parser fails" do
        parser = (token('a') >> Parser(Char, String).pure("left")) |
                 Parser(Char, String).pure("right")
        parser.parse("").should eq("right")
      end

      it "fails if both parsers fail" do
        parser = (token('a') >> Parser(Char, String).pure("left")) |
                 (token('b') >> Parser(Char, String).pure("right"))
        parser.parse("").should be_a(ParseError(Char))
      end
    end

    describe "Proc#^" do
      it "applies the parser (right operand)" do
        parser = ->(x : Char) { x } ^ token('a')
        parser.parse("a").should eq('a')
      end

      it "applies the function (left operand) to the result of the parser (right operand)" do
        parser = ->(x : Int32) { x.to_s } ^ Parser(Char, Int32).pure(1)
        parser.parse("").should eq("1")
      end

      it "auto-curries the function" do
        combine = ->(x : Int32, y : Char, z : String) { "#{x}, #{y}, #{z}" }
        parser = combine ^ Parser(Char, Int32).pure(1)
        result = parser.parse("")

        result.should_not be_a(ParseError(Char))
        result.call('2').call("3").should eq("1, 2, 3") unless result.is_a?(ParseError)
      end
    end

    describe "#<<" do
      it "applies the left parser, then the right parser" do
        parser = token('a') << token('b')
        parser.parse("ab").should_not be_a(ParseError(Char))
      end

      it "returns the result of the left parser" do
        parser = Parser(Char, String).pure("left") << Parser(Char, String).pure("right")
        parser.parse("").should eq("left")
      end
    end

    describe "#>>" do
      it "applies the left parser, then the right parser" do
        parser = token('a') >> token('b')
        parser.parse("ab").should_not be_a(ParseError(Char))
      end

      it "returns the result of the right parser" do
        parser = Parser(Char, String).pure("left") >> Parser(Char, String).pure("right")
        parser.parse("").should eq("right")
      end
    end

    describe "#<=>" do
      it "applies the left parser, then the right parser" do
        discard = ->(a : Char, b : Char) { nil }
        parser = discard ^ token('a') <=> token('b')
        parser.parse("ab").should_not be_a(ParseError(Char))
      end

      it "applies the left parser's function with the right parser's value as the argument" do
        join = ->(a : Char, b : Char) { "#{a}, then #{b}" }
        parser = join ^ token('a') <=> token('b')
        parser.parse("ab").should eq("a, then b")
      end
    end

    describe "#repeat" do
      it "applies the parser repeatedly within the given bounds" do
        base_parser = token('a') | token('b')
        zero_plus_parser = base_parser.repeat(0..)
        one_plus_parser = base_parser.repeat(1..)
        zero_or_one_parser = base_parser.repeat(..1)
        two_thru_four_parser = base_parser.repeat(2..4)
        two_to_four_parser = base_parser.repeat(2...4)

        zero_plus_parser.parse_to_string("").should eq("")
        zero_plus_parser.parse_to_string("aabb").should eq("aabb")

        one_plus_parser.parse_to_string("a").should eq("a")
        one_plus_parser.parse_to_string("aabb").should eq("aabb")

        zero_or_one_parser.parse_to_string("").should eq("")
        zero_or_one_parser.parse_to_string("b").should eq("b")

        two_thru_four_parser.parse_to_string("ab").should eq("ab")
        two_thru_four_parser.parse_to_string("aba").should eq("aba")
        two_thru_four_parser.parse_to_string("abaa").should eq("abaa")

        two_to_four_parser.parse_to_string("ab").should eq("ab")
        two_to_four_parser.parse_to_string("aba").should eq("aba")
      end

      it "fails if the parser doesn't match enough times" do
        base_parser = token('a') | token('b')
        one_plus_parser = base_parser.repeat(1..)
        two_thru_four_parser = base_parser.repeat(2..4)
        two_to_four_parser = base_parser.repeat(2...4)

        one_plus_parser.parse_to_string("").should be_a(ParseError(Char))

        two_thru_four_parser.parse_to_string("a").should be_a(ParseError(Char))

        two_to_four_parser.parse_to_string("b").should be_a(ParseError(Char))
      end

      it "stops applying the parser after reaching the upper bound" do
        base_parser = token('a') | token('b')
        zero_or_one_parser = base_parser.repeat(..1)
        two_thru_four_parser = base_parser.repeat(2..4)
        two_to_four_parser = base_parser.repeat(2...4)

        zero_or_one_parser.parse_to_string("ba").should be_a(ParseError(Char))

        two_thru_four_parser.parse_to_string("babab").should be_a(ParseError(Char))

        two_to_four_parser.parse_to_string("baba").should be_a(ParseError(Char))
      end
    end

    describe "#ahead" do
      it "matches without consuming input if the parser succeeds" do
        (token('a').ahead >> token('a')).parse("a").should eq('a')
      end

      it "fails if the parser fails" do
        token('a').ahead.parse("").should be_a(ParseError(Char))
        token('a').ahead.parse("c").should be_a(ParseError(Char))
      end
    end

    describe "#not_ahead" do
      it "matches without consuming input if the parser fails" do
        token('a').not_ahead.parse("").should eq(nil)
        (token('a').not_ahead >> token('c')).parse("c").should eq('c')
      end

      it "fails if the parser matches" do
        token('a').not_ahead.parse("a").should be_a(ParseError(Char))
      end
    end
  end

  describe ".letter" do
    it "matches a letter" do
      letter.parse("a").should eq('a')
      letter.parse("Z").should eq('Z')
    end

    it "doesn't match nothing" do
      letter.parse("").should be_a(ParseError(Char))
    end

    it "doesn't match more than one letter" do
      letter.parse("aa").should be_a(ParseError(Char))
    end

    it "doesn't match a non-letter" do
      letter.parse("0").should be_a(ParseError(Char))
      letter.parse("!").should be_a(ParseError(Char))
    end
  end

  describe ".digit" do
    it "matches a digit" do
      digit.parse("0").should eq('0')
      digit.parse("9").should eq('9')
    end

    it "doesn't match nothing" do
      digit.parse("").should be_a(ParseError(Char))
    end

    it "doesn't match more than one digit" do
      digit.parse("00").should be_a(ParseError(Char))
    end

    it "doesn't match a non-digit" do
      digit.parse("a").should be_a(ParseError(Char))
      digit.parse("!").should be_a(ParseError(Char))
    end
  end
end
