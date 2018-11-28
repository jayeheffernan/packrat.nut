const beautify = require('json-beautify');
const { expect } = require('chai');
const R = require('ramda');
const f = o => beautify(o, null, 4, 80);
const p = o => console.log(f(o));
const FRAGMENT_TYPE = {
    NT: 0,
    STRING: 1,
    RE: 2,
    COMPOSITE: 3,
    LOOKAHEAD: 4,
    NEGATIVE_LOOKAHEAD: 5,
    REPETITION: 6,
};

class Fragment {
    constructor(type, value) {
        this._fragment = true;
        this.type = type;
        this.value = value;
    }

    match(input, pos, rules, memos, actions = {}, post = {}) {
        if (this.type === FRAGMENT_TYPE.NT && this.value in memos[pos]) {
            return memos[pos][this.value];
        }
        const match = this._match(input, pos, rules, memos, actions, post);
        let result;
        if (match == null) {
            return null;
        } else {
            if (typeof match === 'number') {
                const consumed = match;
                result = { consumed, value: input.slice(pos, pos+consumed) };
            } else {
                expect(match).to.have.property('value');
                expect(match).to.have.property('consumed').that.is.a('number');
                result = match;
            }
        }
        result.type = this.type;
        result.start = pos;

        if (this.type === FRAGMENT_TYPE.NT) {
            result.name = this.value;
            if (this.value in actions) {
                result.value = actions[this.value](result);
            }
        }

        if (this.type === FRAGMENT_TYPE.NT) {
            memos[pos][this.value] = result;
        }
        expect(result).to.have.property('value');
        expect(result).to.have.property('consumed').that.is.a('number');
        return result;
    }

    _match(input, pos, rules, memos, actions, post) {
        let string = input.slice(pos);
        let matching, match, total, ruleName, options;
        switch (this.type) {
            case FRAGMENT_TYPE.STRING:
                return string.startsWith(this.value) ? this.value.length : null;

            case FRAGMENT_TYPE.RE:
                matching = string.match(this.value);
                if (!matching) {
                    return null;
                }
                [ match ] = matching;
                return match.length;

            case FRAGMENT_TYPE.COMPOSITE:
                options = this.value;
            case FRAGMENT_TYPE.NT:
                options = options || rules[this.value];
                for (let i = 0; i < options.length; i++) {
                    const option = options[i];
                    let good = true;
                    const submatches = [];
                    let start = pos;
                    for (const fragment of option) {
                        const match = fragment.match(input, start, rules, memos, actions);
                        if (match == null) {
                            good = false;
                            break;
                        } else {
                            const { consumed, value } = match;
                            expect(consumed).to.be.a('number');
                            // TODO make this configureable?  Like `actions`?
                            submatches.push(this._post(match));
                            start += consumed;
                        }
                    }
                    if (good) {
                        const ans = { consumed: start - pos, value: submatches, alternative: i };
                        return ans;
                    } else {
                        continue;
                    }
                }
                return null;

            case FRAGMENT_TYPE.REPETITION:
                const { fragment, low, high } = this.value;
                let matches = 0;
                const submatches = [];
                let offset = 0;
                while (matches <= high) {
                    const match = fragment.match(input, pos+offset, rules, memos, actions);
                    if (match == null) {
                        break;
                    } else {
                        expect(match).to.be.an('object').that.has.property('consumed').that.is.a('number');
                        matches += 1;
                        offset += match.consumed;
                        submatches.push(match);
                    }
                }
                if (matches >= low) {
                    return { consumed: offset, value: submatches, times: matches };
                } else {
                    return null;
                }

            case FRAGMENT_TYPE.LOOKAHEAD:
                match = this.value.match(input, pos, rules, memos, actions);
                if (match) {
                    // TODO is this good enough?  How to do it in Squirrel?  We don't want this value being modified accidentally
                    const result = R.clone(match);
                    result.consumed = 0;
                    result.value = [];
                    return result;
                } else {
                    return null;
                }

            case FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD:
                match = this.value.match(input, pos, rules, memos, actions);
                if (match) {
                    return null;
                } else {
                    const result = { name: this.value.value, consumed: 0, value: [] };
                    return result;
                }

            default:
                throw new Error('default case');
        }
    }

    // Post-processing (after cache, before adding to parse tree)
    // TODO we should have this take the match and the array of submatches to be inserted into
    // that way we can drop values (e.g. for lookaheads)
    _post(match) {
        expect(match).to.be.an('object').that.include.all.keys(['consumed', 'type', 'value']);
        if ([FRAGMENT_TYPE.STRING, FRAGMENT_TYPE.RE].includes(match.type)) {
            return match.value;
        } else if ([FRAGMENT_TYPE.LOOKAHEAD, FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD].includes(match.type)) {
            return null;
        } else {
            return match;
        }
    }

    static nt(name) {
        return new Fragment(FRAGMENT_TYPE.NT, name);
    }

    static re(str) {
        return new Fragment(FRAGMENT_TYPE.RE, '^' + str);
    }

    static str(str) {
        return new Fragment(FRAGMENT_TYPE.STRING, str);
    }

    static composite(opts) {
        return new Fragment(FRAGMENT_TYPE.COMPOSITE, opts);
    }

    static rep(fragment, low=0, high=Infinity) {
        return new Fragment(FRAGMENT_TYPE.REPETITION, { fragment, low, high });
    }

    static la(fragment) {
        return new Fragment(FRAGMENT_TYPE.LOOKAHEAD, fragment);
    }

    static nla(fragment) {
        return new Fragment(FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD, fragment);
    }
}
const F = Fragment;

const grammarRules = {
    grammar: [
        [F.nt('whitespace'), F.rep(F.nt('rule'), 1)],
    ],
    identifier: [
        [F.re('(\\w|\\d|_)+')],
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
        [F.nt('whitespace'), F.str('|'), F.nt('whitespace'), F.nt('ruleRhs')],
        [],
    ],
    ruleOption: [
        [F.str('epsilon')],
        [F.nt('fragment'), F.nt('ruleOptionSuffix')],
    ],
    ruleOptionSuffix: [
        [F.nt('break'), F.nt('fragment'), F.nt('ruleOptionSuffix')],
        [],
    ],
    fragment: [
        [
            F.nla(F.composite([ [F.nt('identifier'), F.nt('arrow')] ])),
            F.composite([
                [F.nt('repetition')],
                [F.nt('normalFragment')],
            ]),
        ],
    ],
    normalFragment: [
        [F.str('!'), F.nt('fragment')],
        [F.str('&'), F.nt('fragment')],
        [F.nt('composite')],
        [F.nt('nonterminal')],
        [F.nt('string')],
        [F.nt('re')],
    ],
    repetition: [
        [F.nt('normalFragment'), F.composite([[F.str('?')], [F.str('*')], [F.str('+')]])],
    ],
    composite: [
        [F.str('('), F.nt('ruleRhs'), F.str(')')],
    ],
    nonterminal: [
        [F.nt('identifier')],
    ],
    string: [
        [F.str("'"), F.nt('chars'), F.str("'")],
    ],
    chars: [
        [F.re(`[^']*`)],
    ],
    re: [
        [F.str('/'), F.re('[^/]+'), F.str('/')],
    ],
    whitespace: [
        [F.re('\\s*')],
    ],
    break: [
        [F.re('\\s+')],
    ],
};
const grammarActions = {
    whitespace: match => null,
    chars: match => match.value[0],
    string: match => F.str(match.value[1].value),
    nonterminal: match => F.nt(match.value[0].value),
    re: match => F.re(match.value[1]),
    composite: match => {
        return F.composite(match.value[1].value);
    },
    repetition: match => {
        expect(match.value).to.be.an('array').of.length(2);
        expect(match.value[1].value).to.be.an('array').of.length(1);
        const fragment = match.value[0].value;
        const repChar = match.value[1].value[0];
        const times = { "?": [0, 1], "*": [0, Infinity], "+": [1, Infinity] }[repChar];
        return F.rep(fragment, times[0], times[1]);
    },
    fragment: match => {
        const composite = match.value[1];
        expect(composite.value).to.be.an('array').of.length(1);
        return composite.value[0].value;
    },
    normalFragment: match => {
        const fragment = match.value[match.value.length-1].value;
        if (match.alternative === 0) {
            return F.nla(fragment);
        } else if (match.alternative === 1) {
            return F.la(fragment);
        } else {
            return fragment;
        }
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
                const fragment = match.value[1].value;
                const rest = match.value[2].value;
                return [fragment, ...rest];
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
                return match.value[3].value;
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

function parse(ruleName, input, rules, actions) {
    if (typeof rules === 'string') {
        rules = parse('grammar', rules, grammarRules, grammarActions);
        if (!rules) {
            throw new Error('bad grammar');
        }
    }

    // Init cache
    const memos = [];
    for (let i = input.length; i >= 0; i--) {
        memos.push({});
    }

    const start = Fragment.nt(ruleName);
    start.match(input, 0, rules, memos, actions);

    const match = memos[0][ruleName];
    if (match && match.consumed === input.length) {
        return match.value;
    } else {
        return null;
    }
}

module.exports = {
    FRAGMENT_TYPE,
    Fragment,
    F,
    parse,
};
