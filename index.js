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
additive        <- multitive additiveSuffix?
additiveSuffix  <- '+' additive
multitive       <- number multitiveSuffix?
multitiveSuffix <- ('*' | 'x') multitive
number          <- /\\d+/
`;

// Define our actions
const actions = {
    additive: match => {
        const num = match.value[0].value;
        const suffixes = match.value[1].value;
        return num + (suffixes.length ? suffixes[0].value : 0);
    },
    additiveSuffix: match => match.value[1].value,
    multitive: match => {
        const num = match.value[0].value;
        const suffixes = match.value[1].value;
        return num * (suffixes.length ? suffixes[0].value : 1);
    },
    multitiveSuffix: match => match.value[1].value,
    number: match => Number.parseInt(match.value),
};

// Attempt to parse an a value from our input
const input = '2*3+4x5+10';
const result = parse('additive', input, grammar, actions);
expect(result).to.equal(36);
