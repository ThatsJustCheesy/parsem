module Parsem
  extend self

  struct ParseError(Token)
    struct FailParser
      def to_s(io)
        io << "usage of Parser.fail()"
      end
    end

    struct EndOfInput
      def to_s(io)
        io << "end of input"
      end
    end

    struct OneOf(Token)
      def initialize(@tokens : Array(Token | String))
      end

      def initialize(merging left : OneOf(Token), with right : OneOf(Token))
        initialize(left.@tokens + right.@tokens)
      end

      def to_s(io)
        tokens = @tokens.uniq

        io << case tokens.size
        when 0 then "end of input"
        when 1 then tokens[0]
        when 2 then "#{tokens[0]} or #{tokens[1]}"
        else        "#{tokens[...-2].join(", ")}, #{tokens[-2]} or #{tokens[-1]}"
        end
      end
    end

    struct NoneOf(Token)
      def initialize(@tokens : Array(Token | String))
      end

      def initialize(merging left : NoneOf(Token), with right : NoneOf(Token))
        initialize(left.@tokens + right.@tokens)
      end

      def to_s(io)
        tokens = @tokens.uniq

        io << case tokens.size
        when 0 then "anything"
        else        "none of #{OneOf.new(tokens)}"
        end
      end
    end

    # Not supported by Crystal yet:
    # alias Expected(Token) = Nil | EndOfInput | OneOf(Token) | NoneOf(Token)
    # alias Actual(Token) = FailParser | EndOfInput | Token | Array(Token)

    def initialize(
      @expected : Nil | EndOfInput | OneOf(Token) | NoneOf(Token),
      @actual : FailParser | EndOfInput | Token | Array(Token),
      @remainder : Array(Token)
    )
      # puts "Actual: #{@actual}"
    end

    def to_s(io)
      actual = @actual.is_a?(Array(Token)) ? @actual.as(Array(Token)).join : @actual

      actual = "space" if actual == ' '
      actual = "line break" if actual == '\n'
      actual = "tab" if actual == '\t'

      io << "ParseError: "
      io << (if @expected.nil?
        "unexpected #{actual}"
      else
        "expected #{@expected}, but found #{actual}"
      end)
    end
  end

  private struct Context
    property name : String | Nil

    def initialize(
      *,
      @name : String | Nil = nil
    )
    end

    def clone
      self.class.new(
        name: name
      )
    end

    def clone_without_name
      copy = clone
      copy.name = nil
      copy
    end
  end

  struct Parser(Token, Output)
    # Not supported by Crystal (yet?)
    # record ParseSuccess, output : Token, remainder : Array(Token)

    def initialize(
      @allow_backtrack = false,
      &@parse : (Array(Token), Context) -> ParseError(Token) | NamedTuple(output: Output, remainder: Array(Token))
    )
    end

    def run(input_tokens, context)
      # puts "run for #{input_tokens.join}, name #{context.name}"
      result = @parse.call(input_tokens, context)
      result
    end

    # Applies the parser to `tokens`.
    # If it matches, returns the produced output; otherwise, returns a ParseError.
    def parse(tokens : Array(Token)) : ParseError(Token) | Output
      context = Context.new
      result = run(tokens, context)

      return result if result.is_a?(ParseError)
      return ParseError(Token).new(
        expected: ParseError::EndOfInput.new,
        actual: result[:remainder],
        remainder: result[:remainder]
      ) unless result[:remainder].empty?

      result[:output]
    end

    # Applies the parser to `string`.
    # If it matches, returns the produced output; otherwise, returns a ParseError.
    #
    # Type restriction: `Token` = `Char`
    #
    # TODO: Unicode support
    def parse(string : String)
      parse(string.chars)
    end

    # Applies the parser to `string` and tries to convert the result to a string.
    #
    # If `Output` = `Array(Char)` and the parser matches,
    # returns the produced output `join`d into a string.
    # Otherwise, acts like `parse(String)`.
    #
    # Type restriction: `Token` = `Char`
    #
    # TODO: Unicode support
    def parse_to_string(string : String)
      {% if Output == Array(Char) %}
        map(&.join).parse(string)
      {% else %}
        parse(string)
      {% end %}
    end

    # Returns a parser that consumes no input and produces `constant`.
    def self.pure(constant : Output)
      self.new { |input_tokens| {output: constant, remainder: input_tokens} }
    end

    # Returns a parser that fails unconditionally.
    def self.fail(expected = nil, actual = ParseError::FailParser.new)
      self.new { |input_tokens| ParseError(Token).new(expected, actual, input_tokens) }
    end

    # Choice operator: Returns a parser that applies the left parser. If it fails, but no input
    # was consumed, then applies the right parser instead.
    def |(other : Parser(Token, OtherOutput)) : Parser(Token, Output | OtherOutput) forall OtherOutput
      Parser(Token, Output | OtherOutput).new do |input_tokens, context|
        result = run(input_tokens, context)

        if !result.is_a?(ParseError) ||
           (!@allow_backtrack && result.@remainder.size != input_tokens.size)
          result
        else
          # puts "failed: #{input_tokens.join} /// result: #{result}"
          # puts "left backtracked" if @allow_backtrack && result.@remainder.size != input_tokens.size

          other_result = other.run(input_tokens, context)

          if !other_result.is_a?(ParseError) ||
             (!other.@allow_backtrack && other_result.@remainder.size != input_tokens.size)
            other_result
          else
            # puts "failed: #{input_tokens.join} /// result: #{result}"
            # puts "right backtracked" if other.@allow_backtrack && other_result.@remainder.size != input_tokens.size

            my_expected = result.@expected
            other_expected = other_result.@expected

            if my_expected.is_a?(ParseError::OneOf) && other_expected.is_a?(ParseError::OneOf)
              next ParseError(Token).new(
                ParseError::OneOf.new(merging: my_expected, with: other_expected),
                other_result.@actual,
                other_result.@remainder
              )
            elsif my_expected.is_a?(ParseError::NoneOf) && other_expected.is_a?(ParseError::NoneOf)
              next ParseError(Token).new(
                ParseError::NoneOf.new(merging: my_expected, with: other_expected),
                other_result.@actual,
                other_result.@remainder
              )
            else
              other_result
            end
          end
        end
      end
    end

    # Sequencing left-yield operator: Returns a parser that applies the left parser,
    # and if that succeeds, then the right parser.
    # On success, discards the output of the right parser.
    def <<(other : Parser(Token, OtherOutput)) : self forall OtherOutput
      self.class.new do |input_tokens, context|
        my_result = run(input_tokens, context)
        next my_result if my_result.is_a?(ParseError)

        other_result = other.run(
          my_result[:remainder],
          # Subsequent parsers should not inherit this parser's name
          context.clone_without_name
        )
        next other_result if other_result.is_a?(ParseError)

        {output: my_result[:output], remainder: other_result[:remainder]}
      end
    end

    # Sequencing right-yield operator: Returns a parser that applies the left parser,
    # and if that succeeds, then the right parser.
    # On success, discards the output of the left parser.
    def >>(other : Parser(Token, OtherOutput)) : Parser(Token, OtherOutput) forall OtherOutput
      Parser(Token, OtherOutput).new do |input_tokens, context|
        my_result = run(input_tokens, context)
        next my_result if my_result.is_a?(ParseError)

        other.run(
          my_result[:remainder],
          # Subsequent parsers should not inherit this parser's name
          context.clone_without_name
        )
      end
    end

    # Sequencing proc-apply operator: Returns a parser that applies the left parser,
    # and if that succeeds, then the right parser.
    #
    # On success, calls the output of the left parser, which must be a proc (function),
    # with the output of the right parser as its sole argument. Produces as output
    # the result of that call.
    #
    # To create a valid left-hand-side parser for this operation, use `Proc#^(Parser)`.
    def <=>(other : Parser(Token, OtherOutput)) forall OtherOutput
      # I still can't believe this worked
      # Dear Crystal devs: Can I has type restrictions on self? Pretty please
      Parser(Token, typeof(
        run([] of Token, Context.new)
          .as({output: Output, remainder: Array(Token)})[:output]
          .call(
            other.run([] of Token, Context.new)
              .as({output: OtherOutput, remainder: Array(Token)})[:output]
          )
      )).new do |input_tokens, context|
        my_result = run(input_tokens, context)
        next my_result if my_result.is_a?(ParseError)

        other_result = other.run(
          my_result[:remainder],
          # Subsequent parsers should not inherit this parser's name
          context.clone_without_name
        )
        next other_result if other_result.is_a?(ParseError)

        {output: my_result[:output].call(other_result[:output]), remainder: other_result[:remainder]}
      end
    end

    # Returns a new parser that applies this parser, but without consuming any input.
    def ahead
      Parser(Token, Output).new do |input_tokens, context|
        result = run(input_tokens, context)
        if result.is_a?(ParseError)
          result
        else
          {output: result[:output], remainder: input_tokens}
        end
      end
    end

    # Returns a new parser that applies this parser, without consuming any input.
    # The new parser succeeds when this parser fails, and vice versa.
    def not_ahead
      Parser(Token, Nil).new do |input_tokens, context|
        result = run(input_tokens, context)
        if result.is_a?(ParseError)
          {output: nil, remainder: input_tokens}
        else
          ParseError.new(nil, result[:output], input_tokens)
        end
      end
    end

    # Returns a parser that ascribes the next token to be consumed a human-friendly name,
    # which may be displayed in error messages.
    #
    # If a name is already set, it is replaced.
    def name(name : String)
      self.class.new do |input_tokens, context|
        context.name = name
        # puts "name is now #{name} for #{input_tokens}"
        run(input_tokens, context)
      end
    end

    # Returns a parser that ascribes the next token to be consumed a human-friendly name,
    # which may be displayed in error messages.
    #
    # If a name is already set, it is left alone.
    def name?(name : String)
      self.class.new do |input_tokens, context|
        context.name ||= name
        # puts "name? is now #{name} for #{input_tokens}"
        run(input_tokens, context)
      end
    end

    def allow_backtrack
      self.class.new(true) do |input_tokens, context|
        run(input_tokens, context)
      end
    end

    # def zero_or_more
    #   Parser(Token, Array(Output)).new do |input_tokens, context|
    #     remainder = input_tokens
    #     output = [] of Output
    #     until (result = run(remainder, context)).is_a?(ParseError)
    #       remainder = result[:remainder]
    #       output << result[:output]
    #     end
    #     {output: output, remainder: remainder}
    #   end
    # end

    # def one_or_more
    #   ->Parsem.extend(Token, Array(Token)) ^ self <=> zero_or_more
    # end

    # Returns a parser that applies this parser some number of times within `range`.
    #
    # If this parser succeeds at least `range.begin || 0` times, produces an array of
    # the output values from all the successful applications.
    # Otherwise, fails with the first `ParseError` encountered.
    def repeat(range : Range(B, E)) forall B, E
      Parser(Token, Array(Output)).new do |input_tokens, context|
        remainder = input_tokens
        output = [] of Output

        num_parsed = 0
        until (
                (!range.end.nil? && num_parsed >= (range.end.not_nil! - (range.excludes_end? ? 1 : 0))) ||
                (result = run(remainder, context)).is_a?(ParseError)
              )
          result = result.not_nil!
          num_parsed += 1

          remainder = result[:remainder]
          output << result[:output]
        end

        num_parsed >= (range.begin || 0) ? {output: output, remainder: remainder} :  # Broke out early, so the last result was a ParseError
result.as(ParseError)
      end
    end

    # Returns a parser that applies this parser `count` times.
    #
    # If this parser succeeds all `count` times, produces an array of its output values.
    # Otherwise, fails with the first `ParseError` encountered.
    def repeat(count : Int32)
      repeat(count..count)
    end

    # Returns a parser that applies this parser, and succeeds regardless of the result.
    #
    # If this parser succeeds, produces an array containing its output value.
    # Otherwise, produces an empty array.
    def optional
      # We use `|` instead of `repeat(..1)` so that the parser being made
      # optional still shows up in error messages.
      # `repeat`'s behavior is such that, if the repeated parser fails after
      # the required lower bound is already satisfied, the failure happens
      # silently (i.e., `repeat` just discards the `ParseError`).
      # Future improvments may obviate the need for this special case.
      map { |output| [output] } | Parser(Token, Array(Output)).pure([] of Output)
    end

    # Returns a parser that that applies this parser, then pipes the output through `block`.
    #
    # If this parser succeeds, produces the result of calling `block` with the output value
    # as the argument.
    # Otherwise, fails without calling `block`.
    #
    # This is a block-based convenience wrapper for `Proc#^(Parser)`, with the restriction that
    # the provided block cannot take more than one parameter.
    def map(&block : Output -> NewOutput) forall NewOutput
      block ^ self
    end

    def extend
      ->Parsem.extend(Output, typeof(
        run([] of Token, Context.new)
          .as({output: Output, remainder: Array(Token)})[:output][0]
      )) ^ self
    end

    def concat
      ->Parsem.concat(Output, Output) ^ self
    end

    def flatten
      map &.flatten
    end

    def join
      map &.join
    end
  end

  # Defers the creation of `parser` until it is used.
  # This allows parsers to be composed in terms of each other.
  #
  # WARNING: May incur a performance penalty.
  macro lazy(parser)
    (typeof({{parser}})).new do |input_tokens, context|
      {{parser}}.run(input_tokens, context)
    end
  end

  def token(token : Token) : Parser(Token, Token) forall Token
    Parser(Token, Token).new do |input_tokens, context|
      if !input_tokens.empty? && (next_token = input_tokens.first) == token
        # puts "tok #{token} at #{context.alternation_level}"
        {output: token, remainder: input_tokens[1..]}
      else
        # puts "token #{token} name: #{context.name}"
        ParseError.new(
          ParseError::OneOf.new([context.name || token] of Token | String),
          next_token || ParseError::EndOfInput.new,
          input_tokens
        )
      end
    end
  end

  def not(token : Token) : Parser(Token, Token) forall Token
    Parser(Token, Token).new do |input_tokens, context|
      if !input_tokens.empty? && (next_token = input_tokens.first) != token
        {output: next_token.as(Token), remainder: input_tokens[1..]}
      else
        ParseError.new(
          ParseError::NoneOf.new([context.name || token] of Token | String),
          token,
          input_tokens
        )
      end
    end
  end

  def any(type : Token.class) : Parser(Token, Token) forall Token
    none_of([] of Token)
  end

  def one_of(tokens : Array(Token)) : Parser(Token, Token) forall Token
    Parser(Token, Token).new do |input_tokens, context|
      next_token = input_tokens.first?
      if next_token.nil? || !tokens.includes?(next_token)
        next ParseError.new(
          ParseError::OneOf.new(
            context.name ? [context.name.not_nil!] of Token | String : tokens.map { |t| t.as(Token | String) }
          ),
          next_token || ParseError::EndOfInput.new,
          input_tokens
        )
      end

      {output: next_token, remainder: input_tokens[1..]}
    end
  end

  def none_of(tokens : Array(Token)) : Parser(Token, Token) forall Token
    Parser(Token, Token).new do |input_tokens, context|
      next_token = input_tokens.first?
      if next_token.nil? || tokens.includes?(next_token)
        next ParseError.new(
          ParseError::NoneOf.new(
            context.name ? [context.name.not_nil!] of Token | String : tokens.map { |t| t.as(Token | String) }
          ),
          next_token || ParseError::EndOfInput.new,
          input_tokens
        )
      end

      {output: next_token, remainder: input_tokens[1..]}
    end
  end

  def alternatives(parsers : Array(Parser(Token, Output))) : Parser(Token, Output) forall Token, Output
    parsers.reduce(Parser(Token, Output).fail) do |acc, next_parser|
      acc | next_parser
    end
  end

  def string(string : String) : Parser(Char, String)
    string.chars.reduce(
      Parser(Char, Array(Char)).pure([] of Char)
    ) do |acc, token|
      acc.extend <=> token(token).name?(string)
    end.map(&.join)
  end

  def extend(value : Value, array : Array(Value)) : Array(Value) forall Value
    [value] + array
  end

  def extend(array : Array(Value), value : Value) : Array(Value) forall Value
    array + [value]
  end

  def concat(array_1 : Array(Value), array_2 : Array(Value)) : Array(Value) forall Value
    array_1 + array_2
  end

  def extend_string(char : Char, string : String) : String
    "#{char}#{string}"
  end

  def extend_string(string : String, char : Char) : String
    "#{string}#{char}"
  end

  def concat_string(string_1 : String, string_2 : String) : String
    "#{string_1}#{string_2}"
  end
end

struct Proc(*T, R)
  # Map operator: Returns a parser that applies `parser`, then partially applies
  # this proc with the result of `parser` as the first argument.
  #
  # If this proc takes more than one argument, it will be implicitly
  # [curried](https://en.wikipedia.org/wiki/Currying).
  # In this case, the actual underlying proc is called once all of its arguments
  # have been provided by additional parsers, applied with `Parser#<=>(Parser)`.
  def ^(parser : Parser(Token, Output)) forall Token, Output
    {% if T.size > 1 %}
      self.curry ^ parser
    {% else %}
      Parser(Token, R).new do |input_tokens, context|
        parser_result = parser.run(input_tokens, context)
        next parser_result if parser_result.is_a?(ParseError)

        {output: self.call(parser_result[:output]), remainder: parser_result[:remainder]}
      end
    {% end %}
  end

  # [Curries](https://en.wikipedia.org/wiki/Currying) this proc.
  #
  # This exists to help implement `Proc#^(Parser)`, but you can use it yourself if you want.
  def curry
    {% begin %}
      {% for i in 0...T.size %}
        ->(arg_{{i}} : {{T[i]}}) {
      {% end %}
          self.call(
            {% for i in 0...T.size %}
              arg_{{i}},
            {% end %}
          )
      {% for i in 0...T.size %}
        }
      {% end %}
    {% end %}
  end

  # Alternative (probably less efficient) implementation:
  #
  # def curry
  #   {% begin %}
  #     curry_n(self, {{T.size}})
  #   {% end %}
  # end
  #
  # private macro curry_n(proc, n)
  #   {% if n > 1 %}
  #     ->(%arg : {{T[T.size - n]}}) { curry_n({{proc}}.partial(%arg), {{n - 1}}) }
  #   {% else %}
  #     {{proc}}
  #   {% end %}
  # end
end
