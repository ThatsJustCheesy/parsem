require "./parser"

module Parsem
  # TODO: Unicode support
  def letter : Parser(Char, Char)
    letters = "abcdefghijklmnopqrstuvwxyz"
    (Parsem.one_of(letters.chars) | Parsem.one_of(letters.upcase.chars)).name?("letter")
  end

  # TODO: Unicode support
  def digit : Parser(Char, Char)
    digits = "0123456789"
    Parsem.one_of(digits.chars).name?("digit")
  end

  # TODO: Unicode support
  def whitespace : Parser(Char, Char)
    whitespace = " \t\r\n"
    Parsem.one_of(whitespace.chars).name?("whitespace")
  end

  def ws
    whitespace.repeat(0..)
  end
end
