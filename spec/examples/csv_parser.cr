require "../spec_helper"

include Parsem

# Adapted from https://github.com/kareman/FootlessParser#csv-parser
# Thanks!

DELIMITER = ','
QUOTE     = '"'
NEWLINE   = '\n'

quoted_cell = token(QUOTE) >> not(QUOTE).repeat(..).join << token(QUOTE)
unquoted_cell = none_of([DELIMITER, NEWLINE]).repeat(..).join
cell = quoted_cell | unquoted_cell

row = (cell << token(DELIMITER)).repeat(..).extend <=> cell
csv = (row << token(NEWLINE)).repeat(..).extend <=> row

describe "example CSV parser" do
  it "parses a cell" do
    csv.parse("hello").should eq([
      ["hello"],
    ])
  end

  it "parses a row with multiple cells" do
    csv.parse("hello,there, 123 ").should eq([
      ["hello", "there", " 123 "],
    ])
  end

  it "parses multiple rows" do
    csv.parse("one\ntwo\nthree").should eq([
      ["one"],
      ["two"],
      ["three"],
    ])
  end

  it "parses multiple rows of varying size" do
    csv.parse("row,number,1\nnext,row").should eq([
      ["row", "number", "1"],
      ["next", "row"],
    ])
  end
end
