require "../spec_helper"

include Parsem

enum UnaryOperator
  Plus
  Minus
end
record UnaryOperation, operator : UnaryOperator, operand : Expression

enum BinaryOperator
  Add
  Subtract
  Multiply
  Divide
end
record BinaryOperation, left : Expression, operator : BinaryOperator, right : Expression

record ParenthesizedGroup, grouped : Expression

class Expression
  alias Value = Int64 | UnaryOperation | BinaryOperation | ParenthesizedGroup

  property value : Value

  def initialize(@value : Expression::Value)
  end

  def_equals @value
end

# Initially defined here, and used with lazy() macro below, to allow for mutual recursion.
# (The real definition depends on other parsers that depend on this parser.)
expression = Parser(Char, Expression).fail

integer = Parsem.digit.repeat(1..)
  .map(&.join.to_i64)
  .map { |i| Expression.new(i) }
  .name("integer")

parenthesized_group =
  infer(->Expression.new) ^
    (infer(->ParenthesizedGroup.new) ^
      token('(') >> lazy(expression) << token(')'))

unary_operator = alternatives([
  {'+', UnaryOperator::Plus},
  {'-', UnaryOperator::Minus},
].map { |char, op| token(char).map { op } })
unary_operation =
  infer(->Expression.new) ^
    (infer(->UnaryOperation.new) ^
      unary_operator <=>
      lazy(expression))

binary_multiply = token('*').map { BinaryOperator::Multiply }
binary_divide = token('/').map { BinaryOperator::Divide }

binary_add = token('+').map { BinaryOperator::Add }
binary_subtract = token('-').map { BinaryOperator::Subtract }

unary_expression = ws >> (parenthesized_group | unary_operation | integer) << ws

multiply_operation = \
   ->(first : Expression, rest : Array({BinaryOperator, Expression})) {
    rest.reduce(first) { |left, (op, right)| Expression.new(BinaryOperation.new(left, op, right)) }
  } ^
   unary_expression <=>
   (
     ->Tuple.new(BinaryOperator, Expression) ^
     (binary_multiply | binary_divide) <=>
     lazy(unary_expression)
   ).repeat(..)

add_operation = \
   ->(first : Expression, rest : Array({BinaryOperator, Expression})) {
    rest.reduce(first) { |left, (op, right)| Expression.new(BinaryOperation.new(left, op, right)) }
  } ^
   multiply_operation <=>
   (
     ->Tuple.new(BinaryOperator, Expression) ^
     (binary_add | binary_subtract) <=>
     lazy(multiply_operation)
   ).repeat(..)

expression = ws >> add_operation << ws

describe "example arithmetic expression parser" do
  it "parses integers" do
    expression.parse("0").should eq(Expression.new(0))
    expression.parse("12345").should eq(Expression.new(12345))
  end

  it "parses unary operations" do
    expression.parse("+1").should eq(Expression.new(UnaryOperation.new(:plus, Expression.new(1))))
    expression.parse("- 1").should eq(Expression.new(UnaryOperation.new(:minus, Expression.new(1))))
  end

  it "parses binary operations" do
    expression.parse("1+2").should eq(Expression.new(BinaryOperation.new(Expression.new(1), :add, Expression.new(2))))
    expression.parse("1 - 2").should eq(Expression.new(BinaryOperation.new(Expression.new(1), :subtract, Expression.new(2))))
    expression.parse("1* 2").should eq(Expression.new(BinaryOperation.new(Expression.new(1), :multiply, Expression.new(2))))
    expression.parse("1 /2").should eq(Expression.new(BinaryOperation.new(Expression.new(1), :divide, Expression.new(2))))
  end

  it "parses grouped expressions" do
    expression.parse("()").should be_a(ParseError(Char))
    expression.parse("( )").should be_a(ParseError(Char))
    expression.parse("(1)").should eq(Expression.new(ParenthesizedGroup.new(Expression.new(1))))
    expression.parse("( 2 ) + (3 + 4)").should eq(
      Expression.new(BinaryOperation.new(
        Expression.new(ParenthesizedGroup.new(
          Expression.new(2)
        )),
        :add,
        Expression.new(ParenthesizedGroup.new(
          Expression.new(BinaryOperation.new(
            Expression.new(3),
            :add,
            Expression.new(4)
          ))
        ))
      ))
    )
  end

  it "parses binary operations left-associatively" do
    expression.parse("1 - 2 + 3").should eq(
      Expression.new(BinaryOperation.new(
        Expression.new(BinaryOperation.new(
          Expression.new(1),
          :subtract,
          Expression.new(2),
        )),
        :add,
        Expression.new(3)
      ))
    )
  end

  it "parses binary operations with correct precedence rules" do
    expression.parse("1 - 2 * 3").should eq(
      Expression.new(BinaryOperation.new(
        Expression.new(1),
        :subtract,
        Expression.new(BinaryOperation.new(
          Expression.new(2),
          :multiply,
          Expression.new(3),
        ))
      ))
    )
  end
end
