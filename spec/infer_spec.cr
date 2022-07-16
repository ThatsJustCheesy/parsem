require "./spec_helper"

include Parsem

record Foo, int32 : Int32 do
  def self.class_method(string : String)
    "class_method got #{string}"
  end
end

describe Parsem do
  describe "::infer" do
    it "works with initializers" do
      make_a_foo = infer(->Foo.new)

      make_a_foo.call(123).should eq(Foo.new(123))
    end
  end

  it "works with class methods" do
    next
    class_method_proc = infer(->Foo.class_method)

    class_method_proc.call("a string").should eq("class_method got a string")
  end
end
