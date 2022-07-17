require "./parser"

module Parsem
  # Parses a letter of the Latin alphabet (a–z, A–Z).
  #
  # TODO: Unicode support
  def letter : Parser(Char, Char)
    letters = "abcdefghijklmnopqrstuvwxyz"
    (Parsem.one_of(letters.chars) | Parsem.one_of(letters.upcase.chars)).name?("letter")
  end

  # Parses a decimal digit (0–9).
  #
  # TODO: Unicode support
  def digit : Parser(Char, Char)
    digits = "0123456789"
    Parsem.one_of(digits.chars).name?("digit")
  end

  # Parses a whitespace character (space, `\t`, `\r`, `\n`).
  #
  # TODO: Unicode support
  def whitespace : Parser(Char, Char)
    whitespace = " \t\r\n"
    Parsem.one_of(whitespace.chars).name?("whitespace")
  end

  # Shortcut for zero or more `#whitespace` characters.
  def ws
    whitespace.repeat(0..)
  end
end
