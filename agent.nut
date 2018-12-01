@include "./libs/PrettyPrinter.nut"
@include "./libs/utils.nut"
@include "./shared/packrat.nut"

// Define our grammar
grammar <-  @"
additive        <- multitive additiveSuffix?
additiveSuffix  <- '+' additive
multitive       <- number multitiveSuffix?
multitiveSuffix <- ('*' / 'x') multitive
number          <- m/\d+/
";
start <- "additive";

// Define our actions
actions <- {
    "number": @(match) match.v[0].tointeger(),
    "multitiveSuffix": @(match) match.v[1].v,
    "multitive": function(match) {
        local num = match.v[0].v;
        local suffixes = match.v[1].v;
        return num * (suffixes.len() ? suffixes[0].v : 1);
    },
    "additiveSuffix": @(match) match.v[1].v,
    "additive": function(match) {
        local num = match.v[0].v;
        local suffixes = match.v[1].v;
        return num + (suffixes.len() ? suffixes[0].v : 0);
    },
};

// Attempt to parse an a value from our input
input <- "1*2+3*4+5";

grammar <- @"
document  <-  __ (object / array) __
object    <-  '{' pair (',' pair)* '}' / '{' __ '}'
pair      <-  __ string __ ':' value
array     <-  '[' value (',' value)* ']' / '[' __ ']'
value     <-  __ (object / array / string / number / boolean_ / null_) __
string    <-  '""' ('\' m/./ / m/[^""]/)* '""'
number    <-  '-'? ('0' / m/[1-9][0-9]*/) ('.' m/[0-9]+/)? (('e' / 'E') ('+' / '-' / '') m/[0-9]+/)?
boolean_  <-  'true' / 'false'
null_     <-  'null'
__        <-  m/\s*/
";

actions <- {
    "null_": @(match) null, // this time we actually want the value `null`
    "boolean_": @(match) match.v[0].string == "true" ? true : false,
    "number": @(match) match.string.tofloat(),
    // TODO: does not support unicode escape sequences (probably)
    "string": @(match) join(match.v[1].v.map(function(charMatch) {
        if (charMatch.alt == 0) {
            // handles escape codes
            return {
                "b": "\b",
                "f": "\f",
                "n": "\n",
                "r": "\r",
                "t": "\t",
                "\"": "\"",
                "\\": "\\",
            }[charMatch.v[1].string];
        } else {
            assert(typeof charMatch.v == "array");
            assert(charMatch.v.len() == 1);
            return charMatch.v[0].string;
        }
    })),
    "value": @(match) match.v[1].v[0].v,
    "array": function(match) {
        if (match.alt == 1) {
            return [];
        } else {
            local first = match.v[1].v;
            local rest = match.v[2].v.map(@(sub) sub.v[1].v);
            rest.insert(0, first);
            return rest;
        }
    },
    "pair": @(match) [match.v[1].v, match.v[4].v],
    "object": function(match) {
        if (match.alt == 1) {
            return {};
        } else {
            local first = match.v[1].v;
            local pairs = match.v[2].v.map(@(sub) sub.v[1].v);
            pairs.insert(0, first);
            local object = {};
            foreach (pair in pairs) {
                object[pair[0]] <- pair[1];
            }
            return object;
        }
    },
    "document": @(match) match.v[1].v[0].v,
};

input <- "@{include('input.json')|escape}";
start <- "document";

// server.log("input:" + input);
result <- parse(start, input, grammar, actions, false);
server.log("output:" + pformat(result.type));
