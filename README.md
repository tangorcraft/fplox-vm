# Lazarus (free pascal) implementation of Lox language

From [Crafting Interpreters](https://craftinginterpreters.com/) book.

## Implementing bytecode virual machine variant of Lox interpereter.

Currently completed chapters:
* Virtual machine;
  * No global states like in book, all VM data is wrapped in classes;
* Scanning on demand;
  * Implemented constant indexes greather than 255 with separate instruction;
* Compiling expressions;
  * Compiler is a class too, makes things simpler;
* Types of values;
* Strings;
* Hash tables;
  * Implemented hash set using "separate chaining" method for string interning;
  * Implementing SipHash (siphash-1-3)
  * Probe sequence is a bit different from linear probe;
* Global variables;
* Local variables;
* Jumping back and forth;
  * The book say that implementation is Turing complete at this point, so I decided to publish it to github;

I'm going to add tests from original Lox repository and implement a way to easily load them into the app, before proceeding to the next chapter.

# License (GPL 3.0 or later)

Copyright (C) 2026  Ivan Markov (TangorCraft)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
