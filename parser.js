const beautify = require('json-beautify');
const { expect } = require('chai');
const R = require('ramda');
const f = o => beautify(o, null, 4, 80);
const p = o => console.log(f(o));
const FRAGMENT_TYPE = {
    RE: 0,
    NT: 1,
    COMPOSITE: 2,
    STRING: 3,
    REPETITION: 4,
    LOOKAHEAD: 5,
    NEGATIVE_LOOKAHEAD: 6,
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

        if (this.type === FRAGMENT_TYPE.NT) {
            result.name = this.value;
            if (this.value in actions) {
                result.value = actions[this.value](result);
            }
//        } else if ([FRAGMENT_TYPE.STRING, FRAGMENT_TYPE.RE].includes(this.type) && this.type in actions) {
//                result.value = actions[this.value](result.value);
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
                while (matches < high) {
                    const match = fragment.match(input, pos+offset, rules, memos, actions);
                    if (match == null) {
                        break;
                    } else {
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

function parse(ruleName, input, rules, actions) {
    const NTs = Object.keys(rules).map(nt => Fragment.nt(nt));
    rules._ = [[Fragment.nt(ruleName)]];

    // Init cache
    const memos = [];
    for (let i = input.length; i >= 0; i--) {
        memos.push({});
    }

    for (let i = input.length; i >= 0; i--) {
        for (const nt of NTs) {
            nt.match(input, i, rules, memos, actions);
        }
    }

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
    F: Fragment,
    parse,
};
