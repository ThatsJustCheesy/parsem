# Parsem

Crystal library for [Parsec][parsec]-like _parser combinators_, which allow you to construct complex parsers out of simpler ones. Usually, this leads to highly compact parsing code, with a structure that very much resembles the grammar itself.

Heavily inspired by [FootlessParser][footless], a parser combinator library for Swift.

[parsec]: https://wiki.haskell.org/Parsec
[footless]: https://github.com/kareman/FootlessParser

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     parsem:
       github: ThatsJustCheesy/parsem
   ```

2. Run `shards install`

## Usage

```crystal
require "parsem"
```

Begin by finding or creating a right-recursive grammar for the language you want to parse. Then translate the grammar into Parsem parsers.

You'll make frequent use of these combinators:

- Sequencing operators: Run the left parser, then the right parser
  - Left-yield `<<`
    - Keeps only the result of the left parser
  - Right-yield `>>`
    - Keeps only the result of the right parser
  - Proc-apply `<=>`
    - Effectively keeps the result of both parsers, but must be used in conjunction with `^` (map operator)
- Choice operator `|`
  - Runs the left parser; if it fails without consuming any input, runs the right parser instead
- Map operator `^`
  - Partially applies the (left) proc with the (right) parser's result as the first argument. Supply any additional arguments with `<=>` (sequencing proc-apply operator)

For now, please see the [specs](tree/main/spec/) for usage examples.

## Contributing

1. Fork it (<https://github.com/ThatsJustCheesy/parsem/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Ian Gregory](https://github.com/ThatsJustCheesy) - creator and maintainer
