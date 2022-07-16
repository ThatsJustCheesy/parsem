module Parsem
  # Attempts to infer the parameter types of a `->A.b` proc literal.
  #
  # For example:
  #
  #     record Foo, int32 : Int32
  #
  #     make_a_foo = infer(->Foo.new)
  #     make_a_foo.call(123) # => Foo(@int32 = 123)
  #
  # This macro has some finicky requirements:
  # - The proc literal must have a type name as receiver (like `->A.b`, not `->a.b` or `->b`)
  # - The receiver must have exactly one method definition with the given name (no overloads)
  # - That method definition must have type restrictions on all of its parameters
  # - Those type restrictions must resolve correctly from the caller's context
  #   - Nested types (`A::B`) should be fully qualified (not written as just `B`)
  #   - Generic type parameters cannot be used
  #
  # If you can't satisfy these requirements, you can't use this macro.
  # In that case, specify the parameter types manually as usual, like `->A.b(Int32)`.
  macro infer(proc_pointer, file = __FILE__, line = __LINE__)
    {% err_msg_prefix = proc_pointer.filename + ":#{proc_pointer.line_number}:#{proc_pointer.column_number}: " %}
    {{ raise err_msg_prefix + "`infer` macro requires a -> proc literal as its argument" unless proc_pointer.is_a?(ProcPointer) }}
    {{ raise err_msg_prefix + "-> proc literal passed to `infer` macro must have a receiver (`->Foo.foo`, not `->foo`)" if proc_pointer.obj.nil? }}

    {% selector = proc_pointer.name == "new" ? "initialize" : proc_pointer.name %}
    {% methods = proc_pointer.obj.resolve.methods.select { |m| m.name == selector } %}
    {{ raise err_msg_prefix + "no method named #{selector}" if methods.empty? }}
    {{ raise err_msg_prefix + "more than one method named #{selector}: #{methods}" if methods.size > 1 }}

    {% method = methods.first %}

    {{ proc_pointer }}( \
      {% for arg, index in method.args %} \
        {{ raise err_msg_prefix + "argument #{index} of method #{selector} needs a type restriction" unless arg.restriction }} \
        {{ arg.restriction.resolve }},
      {% end %}
    )
  end
end
