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
    "number": @(match) match.value[0].tointeger(),
    "multitiveSuffix": @(match) match.value[1].value,
    "multitive": function(match) {
        local num = match.value[0].value;
        local suffixes = match.value[1].value;
        return num * (suffixes.len() ? suffixes[0].value : 1);
    },
    "additiveSuffix": @(match) match.value[1].value,
    "additive": function(match) {
        local num = match.value[0].value;
        local suffixes = match.value[1].value;
        return num + (suffixes.len() ? suffixes[0].value : 0);
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
    "boolean_": @(match) match.value[0] == "true" ? true : false,
    "number": @(match) input.slice(match.start, match.start+match.consumed).tofloat(),
    // TODO: does not support unicode escape sequences (probably)
    "string": @(match) join(match.value[1].value.map(function(charMatch) {
        if (charMatch.alternative == 0) {
            // handles escape codes
            return {
                "b": "\b",
                "f": "\f",
                "n": "\n",
                "r": "\r",
                "t": "\t",
                "\"": "\"",
                "\\": "\\",
            }[charMatch.value[1]];
        } else {
            assert(typeof charMatch.value == "array");
            assert(charMatch.value.len() == 1);
            return charMatch.value[0];
        }
    })),
    "value": @(match) match.value[1].value[0].value,
    "array": function(match) {
        if (match.alternative == 1) {
            return [];
        } else {
            local first = match.value[1].value;
            local rest = match.value[2].value.map(@(sub) sub.value[1].value);
            rest.insert(0, first);
            return rest;
        }
    },
    "pair": @(match) [match.value[1].value, match.value[4].value],
    "object": function(match) {
        if (match.alternative == 1) {
            return {};
        } else {
            local first = match.value[1].value;
            local pairs = match.value[2].value.map(@(sub) sub.value[1].value);
            pairs.insert(0, first);
            local object = {};
            foreach (pair in pairs) {
                object[pair[0]] <- pair[1];
            }
            return object;
        }
    },
    "document": @(match) match.value[1].value[0].value,
};

input <- "@{include('input.json')|escape}";
start <- "document";

// server.log("input:" + input);
result <- parse(start, input, grammar, actions, false);
server.log("output:" + pformat(result.type));
