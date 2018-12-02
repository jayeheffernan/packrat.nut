@include "./libs/PrettyPrinter.nut"
@include "./Packrat.class.nut"
@include "./grammar_builder.nut"
@include "./grammar.grammar.nut"

// A utility function we'll use later
// Join an array of things into a string, separated by sep
function join(arr, sep="") {
    if (arr.len() == 0)
        return "";
    local s = "" + arr[0];
    for (local i = 1; i < arr.len(); i++) {
        s += sep + arr[i];
    }
    return s;
}

// Define our JSON grammar
rules <- @"
document  <-  __ (object / array) __
object    <-  '{' pair (-',' pair)* '}' / '{' __ '}'
pair      <-  __ string __ ':' value
array     <-  '[' value (-',' value)* ']' / '[' __ ']'
value     <-  __ (object / array / string / number / boolean_ / null_) __
string    <-  '""' (-'\' +m/./ / +m/[^""]/)* '""'
number    <-  '-'? ('0' / m/[1-9][0-9]*/) ('.' m/[0-9]+/)? (('e' / 'E') ('+' / '-' / '') m/[0-9]+/)?
boolean_  <-  'true' / 'false'
null_     <-  'null'
__        <-  m/\s*/

%discard __
%discard_strings
%discard_regexps
";

// Define our JSON parsing actions
actions <- {
    "null_": @(match) null,
    "boolean_": @(match) match.alt == 0 ? true : false,
    "number": @(match) match.string.tofloat(),
    // TODO: does not support unicode escape sequences (probably)
    "string": @(match) join(match.v[0].v.map(function(charMatch) {
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
            }[charMatch.v[0].string];
        } else {
            assert(typeof charMatch.v == "array");
            assert(charMatch.v.len() == 1);
            return charMatch.v[0].string;
        }
    })),
    "value": @(match) match.v[0].v[0].v,
    "array": function(match) {
        if (match.alt == 1) {
            return [];
        } else {
            local first = match.v[0].v;
            local rest = match.v[1].v.map(@(sub) sub.v[0].v);
            rest.insert(0, first);
            return rest;
        }
    },
    "pair": @(match) [match.v[0].v, match.v[1].v],
    "object": function(match) {
        if (match.alt == 1) {
            return {};
        } else {
            local first = match.v[0].v;
            local pairs = match.v[1].v.map(@(sub) sub.v[0].v);
            pairs.insert(0, first);
            local object = {};
            foreach (pair in pairs) {
                object[pair[0]] <- pair[1];
            }
            return object;
        }
    },
    "document": @(match) match.v[0].v[0].v,
};

// Import our JSON to a string
input <- "@{include('input.json')|escape}";
// Specifying the starting rule
start <- "document";

// Parse the JSON
result <- Packrat.parse(start, input, rules, actions);
// The JSON has a "type" field at the top level, set to "FeatureCollection",
// which we log
server.log("output:" + result.type);
