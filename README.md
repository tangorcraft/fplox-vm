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
  * Added tests from original Lox repository and implemented a way to easily load them into the app;
* Calls and functions;
  * Added arity check for native function calls;
  * "A really inefficient recursive Fibonacci function" is running around 5 times slower than equivalent program in Python 3.12.2;
    * I have not tried Python 3.7.3, but I doubt it will run that much slower than 3.12.2;
    * I have a guess this is because many things done with macro in clox I had to remake with actual functions and procedures;
    * Adding inline directive did increase the speed, but not much, now it's just 4 times slower than Python;
    * Adding local IP variable to run() didn't give much speed increase (there is no "register" equivalent in pascal);
* Closures;
* Garbage collection;
  * This chapter exposed a very nasty bug in my code, it looked really small, but could potentially do a lot of harm (even if it's a toy language), I'm glad it's squshed;
    * There was other bugs with hash tables, but those were very easy to spot just looking at call stack;
  * Back to the performance problem, I found that I was using 32 bit Lazarus 4.6 while on 64 bit Windows 10, so together with an upgrade to Lazarus 4.8, I switched to 64 bit compiler;
    * Fib.lox runs nearly 2 times faster than 32 bit variant, still not as fast as Python, but the difference is just 2 times slower now (down from 5 times slower a few chapters back);
  * Implementing this chapter required a lot of workarounds because free pascal don't allow cyclic dependency in interface section, meaning I can't for example add function like markValue to the interface of memory.pas;
    * If I'm going to make real compiler/interpreter using pascal, I'll need to think about where to put GC from the very start;
* Classes and instances;
  * Added hasField native function to check if instance has a field;
  * Added a way for native functions to trigger runtime error;

# License

For files in "test" directory see [test/LICENSE](test/LICENSE) file.

Each other file in this repository falls under GPL 3.0 or later license.

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
