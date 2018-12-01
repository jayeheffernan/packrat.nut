enum SYMBOL_TYPE {
    NT,
    STRING,
    RE,
    COMPOSITE,
    LOOKAHEAD,
    NEGATIVE_LOOKAHEAD,
    REPETITION
};

class Match {
    t = null;
    s = null;
    l = null;
    v = null;

    nt = null; // For NTs only
    alt = null; // For COMPOSITE and NTs only
    n = null; // For REPETITIONs only

    _input = null;

    constructor(l_, v_) {
        l = l_;
        v = v_;
    }

    function _serialize() {
        return { _match=true, t=t, s=s, l=l, v=v, nt=nt, alt=alt, n=n };
        // TODO?
        // foreach (k,v in this.getclass()) {
    }

    function _get(k) {
        switch (k) {
            case "end":
                return s + l;
            case "string":
                return ::strslice(_input, s, s + l);
            default:
                throw "key not found: " + k;
        }
    }

}

class Symbol {
    t = null;
    v = null;

    constructor(t_, v_) {
        t  = t_;
        v = v_;
    }

    function match(input, pos, rules, memos, actions = {}, post = {}) {
        if (t == SYMBOL_TYPE.NT && v in memos[pos]) {
            return memos[pos][v];
        }
        local match = _match(input, pos, rules, memos, actions, post);
        if (match == null) {
            return null;
        }
        match._input = input;
        match.t = t;
        match.s = pos;

        if (t == SYMBOL_TYPE.NT && match.nt in actions) {
            match.v = actions[v](match);
        }

        if (t == SYMBOL_TYPE.NT) {
            memos[pos][v] <- match;
        }
        assert(match.l != null);
        assert(typeof match.l == "integer");
        return match;
    }

    function _match(input, pos, rules, memos, actions, post) {
        local matching, match, total, ruleName, options;
        switch (t) {
            case SYMBOL_TYPE.STRING:
                if (strmatch(input, v, pos)) {
                    return Match(v.len(), strslice(input, pos, pos+v.len()))
                } else {
                    return null;
                }

            case SYMBOL_TYPE.RE:
                //if (input == ::input) server.log("searching " + pos);
                matching = v.search(input, pos);
                if (!matching) return null;
                assert(matching.begin == pos);
                return Match(matching.end - matching.begin, strslice(input, pos, matching.end));

            case SYMBOL_TYPE.COMPOSITE:
                options = v;
            case SYMBOL_TYPE.NT:
                options = options || rules[v];
                for (local i = 0; i < options.len(); i++) {
                    local option = options[i];
                    local good = true;
                    local submatches = [];
                    local s = pos;
                    foreach (sym in option) {
                        local match = sym.match(input, s, rules, memos, actions);
                        if (match == null) {
                            good = false;
                            break;
                        } else {
                            assert(typeof match.l == "integer");
                            s += match.l;
                            // TODO make this configureable?  Like `actions`?
                            submatches.push(_post(match));
                        }
                    }
                    if (good) {
                        local m = Match(s - pos, submatches);
                        if (t == SYMBOL_TYPE.NT) m.nt = v;
                        m.alt = i;
                        return m;
                    } else {
                        continue;
                    }
                }
                return null;

            case SYMBOL_TYPE.REPETITION:
                local sym = v.sym;
                local low = v.low;
                local high = v.high;
                local matches = 0;
                local submatches = [];
                local offset = 0;
                while (high == null || matches <= high) {
                    local match = sym.match(input, pos+offset, rules, memos, actions);
                    if (match == null) {
                        break;
                    } else {
                        assert(match instanceof Match);
                        matches += 1;
                        offset += match.l;
                        submatches.push(match);
                    }
                }
                if (matches >= low) {
                    local m = Match(offset, submatches);
                    m.n = matches;
                    return m;
                } else {
                    return null;
                }

            case SYMBOL_TYPE.LOOKAHEAD:
                match = v.match(input, pos, rules, memos, actions);
                if (match) {
                    return Match(0, null);
                } else {
                    return null;
                }

            case SYMBOL_TYPE.NEGATIVE_LOOKAHEAD:
                match = v.match(input, pos, rules, memos, actions);
                if (match) {
                    return null;
                } else {
                    return Match(0, null);
                }

            default:
                throw "default case";
        }
    }

    // Post-processing (after cache, before adding to parse tree)
    // TODO we should have this take the match and the array of submatches to be inserted into
    // that way we can drop values (e.g. for lookaheads)
    function _post(match) {
        assert(match instanceof Match);
        foreach (key in ["l", "t"]) {
            assert(match[key] != null);
        }
        if ([SYMBOL_TYPE.STRING, SYMBOL_TYPE.RE].find(match.t) != null) {
            return match;
        } else if ([SYMBOL_TYPE.LOOKAHEAD, SYMBOL_TYPE.NEGATIVE_LOOKAHEAD].find(match.t) != null) {
            return null;
        } else {
            return match;
        }
    }

    static function nt(name) {
        return Symbol(SYMBOL_TYPE.NT, name);
    }

    static function re(str) {
        return Symbol(SYMBOL_TYPE.RE, regexp("^" + str));
    }

    static function str(str) {
        return Symbol(SYMBOL_TYPE.STRING, str);
    }

    static function composite(opts) {
        return Symbol(SYMBOL_TYPE.COMPOSITE, opts);
    }

    static function rep(sym, low=0, high=null) {
        return Symbol(SYMBOL_TYPE.REPETITION, { sym=sym, low=low, high=high });
    }

    static function la(sym) {
        return Symbol(SYMBOL_TYPE.LOOKAHEAD, sym);
    }

    static function nla(sym) {
        return Symbol(SYMBOL_TYPE.NEGATIVE_LOOKAHEAD, sym);
    }
}
local F = Symbol;

local grammarRules = {
    "grammar": [
        [F.nt("whitespace"), F.rep(F.nt("rule"), 1)],
    ],
    "identifier": [
        [F.rep(F.composite([ [F.nla(F.str("m/")), F.re("[a-zA-Z0-9_]")] ]), 1)],
    ],
    "arrow": [
        [F.nt("whitespace"), F.str("<-"), F.nt("whitespace")],
    ],
    "rule": [
        [F.nt("identifier"), F.nt("ruleSuffix")],
    ],
    "ruleSuffix": [
        [F.nt("arrow"), F.nt("ruleRhs"), F.nt("whitespace")],
    ],
    "ruleRhs": [
        [F.nt("ruleOption"), F.nt("ruleRhsSuffix")],
    ],
    "ruleRhsSuffix": [
        [F.nt("whitespace"), F.str("/"), F.nt("whitespace"), F.nt("ruleRhs")],
        [],
    ],
    "ruleOption": [
        [F.str("epsilon")],
        [F.nt("symbol"), F.nt("ruleOptionSuffix")],
    ],
    "ruleOptionSuffix": [
        [F.nt("break"), F.nt("symbol"), F.nt("ruleOptionSuffix")],
        [],
    ],
    "symbol": [
        [
            F.nla(F.composite([ [F.nt("identifier"), F.nt("arrow")] ])),
            F.composite([
                [F.nt("repetition")],
                [F.nt("normalSymbol")],
            ]),
        ],
    ],
    "normalSymbol": [
        [F.str("!"), F.nt("symbol")],
        [F.str("&"), F.nt("symbol")],
        [F.nt("nonterminal")],
        [F.nt("composite")],
        [F.nt("string")],
        [F.nt("re")],
    ],
    "repetition": [
        [F.nt("normalSymbol"), F.composite([[F.str("?")], [F.str("*")], [F.str("+")]])],
    ],
    "composite": [
        [F.str("("), F.nt("ruleRhs"), F.str(")")],
    ],
    "nonterminal": [
        [F.nt("identifier")],
    ],
    "string": [
        [F.str("'"), F.nt("chars"), F.str("'")],
    ],
    "chars": [
        [F.re(@"[^']*")],
    ],
    "re": [
        [F.str("m/"), F.re("[^/]+"), F.str("/")],
    ],
    "whitespace": [
        [F.re(@"\s*")],
    ],
    "break": [
        [F.re(@"\s+")],
    ],
};
local grammarActions = {
    "whitespace": @(match) null,
    "chars": @(match) match.v[0].string,
    "string": @(match) F.str(match.v[1].v),
    "nonterminal": @(match) F.nt(match.v[0].v),
    "re": @(match) F.re(match.v[1].string),
    "composite": @(match) F.composite(match.v[1].v),
    "repetition": function(match) {
        assert(typeof match.v == "array");
        assert(match.v.len() == 2);
        assert(typeof match.v[1].v == "array")
        assert(match.v[1].v.len() == 1)
        local sym = match.v[0].v;
        local repChar = match.v[1].v[0].string;
        local times = { "?": [0, 1], "*": [0, null], "+": [1, null] }[repChar];
        return F.rep(sym, times[0], times[1]);
    },
    "symbol": function(match) {
        local composite = match.v[1];
        assert(typeof composite.v == "array");
        assert(composite.v.len() == 1);
        return composite.v[0].v;
    },
    "normalSymbol": function(match) {
        local sym = match.v[match.v.len()-1].v;
        if (match.alt == 0) {
            return F.nla(sym);
        } else if (match.alt == 1) {
            return F.la(sym);
        } else {
            return sym;
        }
    },
    "ruleOption": function(match) {
        if (match.alt == 0) {
            return [];
        } else {
            local sym = match.v[0].v;
            local rest = match.v[1].v;
            rest.insert(0, sym);
            return rest;
        }
    },
    "ruleOptionSuffix": function(match) {
        switch (match.alt) {
            case 0:
                local sym = match.v[1].v;
                local rest = match.v[2].v;
                rest.insert(0, sym);
                return rest;
            case 1:
                return [];
            default:
                throw "unexpected";
        }
    },
    "ruleRhs": function(match) {
        local ruleOption = match.v[0].v;
        local rest = match.v[1].v;
        rest.insert(0, ruleOption);
        return rest;
    },
    "ruleRhsSuffix": function(match) {
        switch (match.alt) {
            case 0:
                return match.v[3].v;
            case 1:
                return [];
            default:
                throw "unexpected";
        }
    },
    "ruleSuffix": @(match) match.v[1].v,
    "identifier": @(match) join(match.v[0].v.map(@(sub) sub.v[1].string)),
    "rule": function(match) {
        local result = {};
        result[match.v[0].v] <- match.v[1].v;
        return result;
    },
    "grammar": @(match) mergeAll(match.v[1].v.map(@(submatch) submatch.v)),
};

function parse(ruleName, input, rules, actions, printMemos=false) {
    if (typeof rules == "string") {
        rules = parse("grammar", rules, grammarRules, grammarActions);
        if (!rules) {
            throw "bad grammar";
        }
    }

    // Init cache
    local memos = [];
    for (local i = input.len(); i >= 0; i--) {
        memos.push({});
    }

    local start = Symbol.nt(ruleName);
    start.match(input, 0, rules, memos, actions);

    if (printMemos) print(memos[0]);
    local match = ruleName in memos[0] ? memos[0][ruleName] : null;
    if (match && match.l == input.len()) {
        return match.v;
    } else {
        return null;
    }
}
