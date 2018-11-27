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

//const rules = {
//    additive: [
//        [F.nt('multitive'), F.nt('additiveSuffix', { times: [1, Infinity] })],
//    ],
//    additiveSuffix: [
//        [F.str('+'), F.nt('additive')],
//        [],
//    ],
//    multitive: [
//        [F.re('\\d+'), F.nt('multitiveSuffix')],
//    ],
//    multitiveSuffix: [
//        [F.composite([[F.str('*')], [F.str('x')]]), F.nt('multitive')],
//        [],
//    ],
//};
//const actions = {
//    additive: ([ multitive, additiveSuffix ]) => multitive.value + additiveSuffix.value,
//    additiveSuffix: subs => subs.length ? subs[1].value : 0,
//    multitive: ([number, multitiveSuffix]) => Number.parseInt(number.value) * multitiveSuffix.value,
//    multitiveSuffix: subs => subs.length ? subs[1].value : 1,
//};
//const input = '4*4x2';
//p(parse('additive', input, rules, actions));

let rules = {
    grammar: [
        [F.nt('whitespace'), F.rep(F.nt('rule'), 1)],
    ],
    identifier: [
        [F.re('\\w+')],
    ],
    arrow: [
        [F.nt('whitespace'), F.str('<-'), F.nt('whitespace')],
    ],
    rule: [
        [F.nt('identifier'), F.nt('ruleSuffix')],
    ],
    ruleSuffix: [
        [F.nt('arrow'), F.nt('ruleRhs'), F.nt('whitespace')],
    ],
    ruleRhs: [
        [F.nt('ruleOption'), F.nt('ruleRhsSuffix')],
    ],
    ruleRhsSuffix: [
        [F.str('/'), F.nt('ruleRhs')],
        [],
    ],
    ruleOption: [
        [F.str('epsilon')],
        [F.nt('fragment'), F.nt('ruleOptionSuffix')],
    ],
    ruleOptionSuffix: [
        [F.nt('break'), F.nt('ruleOption')],
        [],
    ],
    fragment: [
        [
            F.nla(F.composite([ [F.nt('identifier'), F.nt('arrow')] ])),
            F.composite([
                [F.str('!'), F.nt('fragment')],
                [F.str('&'), F.nt('fragment')],
                [F.nt('composite')],
                [F.nt('nonterminal')],
                [F.nt('string')],
                [F.nt('re')],
            ]),
        ],
    ],
    composite: [
        [F.str('('), F.nt('ruleOption'), F.str(')')],
    ],
    nonterminal: [
        [F.nt('identifier')],
    ],
    string: [
        [F.str("'"), F.nt('chars'), F.str("'")],
    ],
    chars: [
        [F.re(`[^"']+`)],
    ],
    re: [
        [F.str('/'), F.re('[^/]'), F.str('/')],
    ],
    whitespace: [
        [F.re('\\s*')],
    ],
    break: [
        [F.re('\\s+')],
    ],
};
const first =  match => match.value[0];
const second = match => match.value[1];
const third =  match => match.value[2];
const ignore = match => null;
const actions = {
    whitespace: ignore,
    chars: first,
    string: match => F.str(match.value[1].value),
    fragment: match => {
        const composite = match.value[1];
        expect(composite.value).to.be.an('array').of.length(1);
        return composite.value[0].value;
    },
    ruleOption: match => {
        if (match.alternative === 0) {
            return [];
        } else {
            const fragment = match.value[0].value;
            const rest = match.value[1].value;
            return [fragment, ...rest];
        }
    },
    ruleOptionSuffix: match => {
        switch (match.alternative) {
            case 0:
                return match.value[1].value;
            case 1:
                return [];
            default:
                throw new Error('unexpected');
        }
    },
    ruleRhs: match => {
        const ruleOption = match.value[0].value;
        const rest = match.value[1].value;
        return [ruleOption, ...rest];
    },
    ruleRhsSuffix: match => {
        switch (match.alternative) {
            case 0:
                return match.value[1].value;
            case 1:
                return [];
            default:
                throw new Error('unexpected');
        }
    },
    ruleSuffix: match => match.value[1].value,
    identifier: match => match.value[0],
    rule: match => ({ [match.value[0].value]: match.value[1].value }),
    grammar: match => R.mergeAll(match.value[1].value.map(submatch => submatch.value)),
};

let input = `
a <- 'b'/'c'
`;
const parsed = parse('grammar', input, rules, actions);
p(parsed);
