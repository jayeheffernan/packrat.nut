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
        [F.nt('whitespace'), F.nt('rule', { times: [1, Infinity] })],
    ],
    identifier: [
        [F.re('\\w(\\w\\d)*')],
    ],
    arrow: [
        [F.nt('whitespace'), F.str('<-'), F.nt('whitespace')],
    ],
    rule: [
        [F.nt('identifier'), F.nt('ruleSuffix')],
    ],
    ruleSuffix: [
        [F.nt('arrow'), F.nt('ruleRhs')],
    ],
    ruleRhs: [
        [F.nt('ruleOption'), F.nt('ruleRhsSuffix')],
    ],
    ruleRhsSuffix: [
        [F.str('/'), F.nt('ruleOption')],
        [],
    ],
    ruleOption: [
        [F.str('epsilon')],
        [F.nt('fragment'), F.nt('ruleOptionSuffix')],
    ],
    ruleOptionSuffix: [
        [F.nt('whitespace'), F.nt('ruleOption')],
        [F.nt('whitespace')],
    ],
    fragment: [
        [
            F.composite([
                [F.nt('identifier'), F.nt('arrow')],
            ], { la: false }),
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
const first = subs => subs[0].value;
const second = subs => subs[1].value;
const third = subs => subs[2].value;
const ignore = subs => null;
let actions = {
    composite: subs => F.composite(subs[1].value),
    nonterminal: subs => F.nt(subs[0].value),
    string: subs => F.str(subs[1].value),
    re: subs => F.re(subs[1].value),
    fragment: subs => {
        if (subs.length === 1) {
            return first(subs);
        } else if (subs[0].name === '!') {
            const fragment =  subs[1].value;
            fragment.modifiers.la = !fragment.modifiers.la;
        } else if (subs[1].name === '&') {
            const fragment =  subs[1].value;
            fragment.modifiers.la = true;
        } else {
            p(subs);
            throw new Error('unexpected');
        }
    },
    whitespace: ignore,
    identifier: first,

    grammar: subs => R.fromPairs(subs.slice(1).map(s => s.value)),
    rule: subs => subs.map(s => s.value),
    ruleSuffix: second,
    ruleRhs: subs => [subs[0].value, ...subs[1].value],
    ruleRhsSuffix: subs => {
        if (subs.length === 0) {
            return [];
        } else {
            return second(subs);
        }
    },
    ruleOption: subs => {
        if (subs.length === 1) {
            return [];
        } else {
            return [subs[0].value, ...subs[1].value];
        }
    },
    ruleOptionSuffix: subs => {
        if (subs.length === 2) {
            return second(subs);
        } else {
            return [];
        }
    },
};

//const input = `
//additive<-multitive additiveSuffix
//
//additiveSuffix<-'+' additive/epsilon
//
//multitive<-/\d+/ multitiveSuffix
//
//multitiveSuffix<-('*'/'x') multitive
//     / epsilon
//`;
let input = `
a <- 'a' 'b'
b <- 'b' 'a'
`;
//actions = R.mapObjIndexed(k => () => null, actions);


input = 'aa';
rules = {
    s: [
        [F.nt('a', { times: [1, Infinity] })],
    ],
    a: [
        [
            F.str('b', { la: false }),
            F.str('a'),
        ],
    ],
};



const parsed = parse('grammar', input, rules, {});
p(parsed);
