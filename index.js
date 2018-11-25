'use strict';
const beautify = require('json-beautify');
const f = o => beautify(o, null, 4, 80);
const p = o => console.log(f(o));
const FRAGMENT_TYPE = {
    RE: 0,
    NT: 1,
    COMPOSITE: 2,
    STRING: 3,
};

class Fragment {
    constructor(type, value, modifiers = { times: [1, 1] }) {
        this.type = type;
        this.value = value;
        this.modifiers = modifiers;
    }

    match(input, pos, actions = {}) {
        if (this.type === FRAGMENT_TYPE.NT && this.value in memos[pos]) {
            return memos[pos][this.value];
        }
        let totalConsumed = 0;
        let matchedTimes = 0;
        const submatches = [];
        const { modifiers: { times: [low, high] } } = this;
        while (matchedTimes < high) {
            const match = this._match(input, pos+totalConsumed);
            if (match == null) {
                break;
            } else {
                let consumed;
                if (typeof match === 'object') {
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
        let result;
        if (matchedTimes >= low) {
            result = { name: this.value, consumed: totalConsumed, value: submatches };
            if (this.value in actions) {
                result.value = actions[this.value](result.value);
            }
        } else {
            result = null;
        }
        if (this.type === FRAGMENT_TYPE.NT) {
            return memoise(this.value, pos, result);
        } else {
            return result;
        }
    }

    _match(input, pos) {
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
                total = 0;
                for (const fragment of this.value) {
                    const consumed = fragment.match(string);
                    if (consumed == null) {
                        return null;
                    } else {
                        string = string.slice(consumed);
                        total += consumed;
                    }
                }
                return total;

            case FRAGMENT_TYPE.NT:
                for (const option of rules[this.value]) {
                    let good = true;
                    const submatches = [];
                    let start = pos;
                    for (const fragment of option) {
                        const match = fragment.match(input, start);
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
}

const F = Fragment;

const rules = {
    additive: [
        [F.nt('multitive'), F.nt('additiveSuffix', { times: [1, Infinity] })],
    ],
    additiveSuffix: [
        [F.str('+'), F.nt('additive')],
        [],
    ],
    multitive: [
        [F.re('\\d+'), F.nt('multitiveSuffix')],
    ],
    multitiveSuffix: [
        [F.str('*'), F.nt('multitive')],
        [],
    ],
};
const actions = {
    additive: ([ multitive, additiveSuffix ]) => multitive.value + additiveSuffix.value,
    additiveSuffix: subs => subs.length ? subs[1].value : 0,
    multitive: ([number, multitiveSuffix]) => Number.parseInt(number.value) * multitiveSuffix.value,
    multitiveSuffix: subs => subs.length ? subs[1].value : 1,
};

const order = ['multitiveSuffix', 'additiveSuffix', 'multitive', 'additive'];
const NTs = order.map(nt => F.nt(nt));

const input = '1+2+3+4*3';

// Init cache
const memos = [{}];
for (const ch of input) {
    memos.push({});
}
function memoise(ruleName, pos, answer) {
    memos[pos][ruleName] = answer;
    return answer;
}

for (let i = input.length; i >= 0; i--) {
    for (const nt of NTs) {
        nt.match(input, i, actions);
    }
}
p(memos[0].additive);
