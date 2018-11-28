'use strict';
const beautify = require('json-beautify');
const { expect } = require('chai');
const R = require('ramda');
const f = o => beautify(o, null, 4, 80);
const p = o => console.log(f(o));
const {
    F,
    parse,
} = require('./parser.js');

// Define our grammar
const grammar = `
document  <-  __ (object | array) __
object    <-  '{' pair (',' pair)* '}' | '{' __ '}'
pair      <-  __ string __ ':' value
array     <-  '[' value (',' value)* ']' | '[' __ ']'
value     <-  __ (object | array | string | number | boolean_ | null_) __
string    <-  '"' ('\\' /./ | /[^"]/)* '"'
number    <-  '-'? ('0' | /[1-9][0-9]*/) ('.' /[0-9]+/)? (('e' | 'E') ('+' | '-' | '') /[0-9]+/)?
boolean_  <-  'true' | 'false'
null_     <-  'null'
__        <-  /\\s*/
`;

// Define our actions
const actions = {
    null_: match => null, // this time we actually want the value `null`
    boolean_: match => match.value[0] === 'true' ? true : false,
    number: match => Number.parseFloat(input.slice(match.start, match.start+match.consumed)),
    string: match => match.value[1].value.map(charMatch => {
        if (charMatch.alternative === 0) {
            // handles escape codes
            return {
                'b': '\b',
                'f': '\f',
                'n': '\n',
                'r': '\r',
                't': '\t',
                '"': '"',
                '\\': '\\',
            }[charMatch.value[1]];
        } else {
            expect(charMatch.value).to.be.an('array').of.length(1);
            return charMatch.value[0];
        }
    }).join(''),
    value: match => match.value[1].value[0].value,
    array: match => {
        if (match.alternative === 1) {
            return [];
        } else {
            const first = match.value[1].value;
            const rest = match.value[2].value.map(sub => sub.value[1].value);
            return [first, ...rest];
        }
    },
    pair: match => [match.value[1].value, match.value[4].value],
    object: match => {
        if (match.alternative === 1) {
            return {};
        } else {
            const first = match.value[1].value;
            const rest = match.value[2].value.map(sub => sub.value[1].value);
            const pairs = [first, ...rest];
            const object = {};
            for (const pair of pairs) {
                object[pair[0]] = pair[1];
            }
            return object;
        }
    },
    document: match => match.value[1].value[0].value,
};

// Attempt to parse an a value from our input
const input =`{
    "vals": [null, true, false, 1.2E3, {}, {"a": 1}, [], [1]],
    "str": "my\\nstring"
}`;
const result = parse('document', input, grammar, actions);
p(result);
