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
};

class Fragment {
    constructor(type, value, modifiers = {}) {
        this.type = type;
        this.value = value;
        this.modifiers = R.merge({
            times: [1, 1],
        }, modifiers);
    }

    match(input, pos, rules, memos, actions = {}) {
        if (this.type === FRAGMENT_TYPE.NT && this.value in memos[pos]) {
            return memos[pos][this.value];
        }
        let totalConsumed = 0;
        let matchedTimes = 0;
        const submatches = [];
        const { modifiers: { times: [low, high] } } = this;
        while (matchedTimes < high) {
            const match = this._match(input, pos+totalConsumed, rules, memos, actions);
            if (match == null) {
                break;
            } else {
                let consumed;
                if (this.type === FRAGMENT_TYPE.NT) {
                    consumed = match.consumed;
                    const subs = match.submatches;
                    submatches.push(subs);
//                    submatches.splice(submatches.length, 0, ...subs);
                } else if (this.type === FRAGMENT_TYPE.COMPOSITE) {
                    consumed = match.consumed;
                    const subs = match.submatches;
                    submatches.splice(submatches.length, 0, ...subs);
                } else {
                    consumed = match;
                    const value = input.slice(pos, pos+consumed);
                    submatches.push(value);
                }
                totalConsumed += consumed;
                matchedTimes += 1;
            }
        }

        let result = null;
        if (matchedTimes >= low) {
            result = { name: this.value, consumed: totalConsumed, value: submatches };
            if (this.type === FRAGMENT_TYPE.NT && this.value in actions) {
                result.value = actions[this.value](result.value);
            } else if ([FRAGMENT_TYPE.RE, FRAGMENT_TYPE.STRING].includes(this.type)) {
                expect(result.value).to.be.an('array').of.length(1);
                result.value = result.value[0];
            }
        }

        if (this.type === FRAGMENT_TYPE.NT) {
            memos[pos][this.value] = result;
        }
        // TODO combine these again
        if (this.modifiers.la != null) {
            if (result == null && this.modifiers.la === false) {
                result = { name: this.value, value: [], consumed: 0 };
            } else if (result != null && this.modifiers.la === true) {
                result = { name: this.value, value: [], consumed: 0 };
            }
        }
        return result;
    }

    _match(input, pos, rules, memos, actions) {
        let string = input.slice(pos);
        let matching, match, total, ruleName;
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
                for (const option of this.value) {
                    let good = true;
                    const submatches = [];
                    let start = pos;
                    for (const fragment of option) {
                        const match = fragment.match(input, start, rules, memos, actions);
                        if (match == null) {
                            good = false;
                            break;
                        } else {
                            const { consumed } = match;
                            submatches.push(match);
                            start += consumed;
                        }
                    }
                    if (good) {
                        const ans = { consumed: start - pos, submatches };
                        return ans;
                    } else {
                        continue;
                    }
                }
                return null;

            case FRAGMENT_TYPE.NT:
                for (const option of rules[this.value]) {
                    let good = true;
                    const submatches = [];
                    let start = pos;
                    for (const fragment of option) {
                        const match = fragment.match(input, start, rules, memos, actions);
                        if (match == null) {
                            good = false;
                            break;
                        } else if (fragment.type === FRAGMENT_TYPE.COMPOSITE) {
                            const { consumed, value } = match;
                            submatches.splice(submatches.length, 0, ...value);
                            start += consumed;
                        } else {
                            const { consumed } = match;
                            submatches.push(match);
                            start += consumed;
                        }
                    }
                    if (good) {
                        const ans = { consumed: start - pos, submatches };
                        return ans;
                    } else {
                        continue;
                    }
                }
                return null;

            default:
                throw new Error('default case');
        }
    }

    static nt(name, mods) {
        return new Fragment(FRAGMENT_TYPE.NT, name, mods);
    }

    static re(str, mods) {
        return new Fragment(FRAGMENT_TYPE.RE, '^' + str, mods);
    }

    static str(str, mods) {
        return new Fragment(FRAGMENT_TYPE.STRING, str, mods);
    }

    static composite(opts, mods) {
        return new Fragment(FRAGMENT_TYPE.COMPOSITE, opts, mods);
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
    p(memos[0]);
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
