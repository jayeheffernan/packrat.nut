# packrat.nut

The first general-purpose parsing library for the Squirrel programming language!

A Packrat parser implementation for Squirrel. Includes a parser-combinator and
grammar-string interfaces for specifying grammars.  See the
[example code](./agent.nut) for an example of how this library can be used to
parse a non-regular language (JSON), given just a definition of the grammar (as
a string) and an action to perform for each grammar item.
