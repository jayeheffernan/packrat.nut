// TODO documentation
enum PR_SYMBOL_TYPE {
    NT,
    STRING,
    RE,
    COMPOSITE,
    LOOKAHEAD,
    NEGATIVE_LOOKAHEAD,
    REPETITION,
    POSITION_ASSERTION,
    BOOLEAN,
    // TODO add another type: "function"
};

// TODO implement chai's expect in Squirrel using this parser!  (or
// maybe an earley parser would be more suited?)  Each chained accessor can add
// the key as a token to an internal array, then calling the chain (_call
// metamethod) can cause it "compile" the tokens to assertions
class Packrat {
    GRAMMAR_DEFAULTS = { discarded={}, discardStrings=false, discardRegexps=false, noDiscardLookaheads=false };
    grammarGrammar = null;
    grammarActions = null;
    buildGrammar   = null;

    // The main parse function
    static function parse(ruleName, input, grammar, actions) {
        if (typeof grammar == "string") {
            if (!(grammarGrammar)) {
                throw "can't parse grammar string: grammar-grammar not available";
            }
            grammar = parse("grammar", grammar, grammarGrammar, grammarActions);
            if (!grammar) {
                throw "bad grammar";
            }
        }

        // make sure flags are available when we go to access them
        grammar.setdelegate(GRAMMAR_DEFAULTS);
        local state = {};

        // Init cache
        local memos = PrMemos(input.len(), ruleName);

        local start = PrSymbol.nt(ruleName);
        start.match(input, 0, grammar, actions, memos, state);

        local match = memos.get(ruleName, 0);
        if (match == PrMemos.NOT_CACHED || match.l != input.len()) {
            return null;
        } else {
            return match.v;
        }
    }

    static function _strslice(str, start, end = null) {
        if (start >= str.len() || start == end) {
            return "";
        } else if (end == null) {
            return str.slice(start);
        } else {
            return str.slice(start, end);
        }
    }

    static function _strmatch(str, substr, pos=0) {
        local l = substr.len();
        if (pos + l > str.len()) return false;
        for (local i = 0; i < l; i++) {
            if (substr[i] != str[pos+i]) return false;
        }
        return true;
    }
}

class PrMatch {
    static DROP = [];
    t = null;
    s = null;
    l = null;
    v = null;

    nt  = null; // For NTs only
    alt = null; // For COMPOSITE and NTs only
    n   = null; // For REPETITIONs only

    _in = null;

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
                return ::Packrat._strslice(_in, s, s + l);
            default:
                throw "key not found: " + k;
        }
    }

}

class PrMemos {
    static NOT_CACHED = [];
    _i = 0;
    _memos = null;
    _map = null;

    constructor(n, start=null) {
        _memos = [];
        _map = {};
        for (local i = 0; i < n+1; i++)
            _memos.push({});
        if (start != null)
            _map[start] <- _i++;
    }

    function cache(nt, pos, value) {
        if (!(nt in _map))
            _map[nt] <- _i++;
        _memos[pos][_map[nt]] <- value;
    }

    function get(nt, pos) {
        if (nt in _map && _map[nt] in _memos[pos]) {
            return _memos[pos][_map[nt]];
        } else {
            return PrMemos.NOT_CACHED;
        }
    }
}

// TODO think about blobs and arrays of tokens
// TODO think about using this as a lexer, and doing a lexer/scanner-based JSON parser
// NB when lexing we can reuse memos throughout
// TODO name things
class PrSymbol {
    t = null;
    v = null;
    // TODO make this trickle down to children (pass it through the match
    // function, if false, so that children don't do work only for the parent
    // to drop it)
    _keep = null;

    constructor(t_, v_, drop=null) {
        t  = t_;
        v = v_;
        _keep = drop == null ? null : !drop;
    }

    function match(input, pos, grammar, actions, memos, state = {}) {
        if (t == PR_SYMBOL_TYPE.NT) {
            local cached = memos.get(v, pos);
            if (cached != PrMemos.NOT_CACHED) {
                return cached;
            }
        }
        local match = _match(input, pos, grammar, actions, memos, state);
        if (match == null) {
            return null;
        }
        match._in = input;
        match.t = t;
        match.s = pos;

        if (t == PR_SYMBOL_TYPE.NT && v in actions) {
            // TODO don't do this if the result is about to be dropped?  Think
            // about effect on cache
            match.v = actions[v](match);
        }

        if (t == PR_SYMBOL_TYPE.NT) {
            memos.cache(v, pos, match);
        }
        assert(match.l != null);
        assert(typeof match.l == "integer");
        return match;
    }

    function _match(input, pos, grammar, actions, memos, state) {
        local matching, match, total, ruleName, options;
        // TODO change this to if-elses
        switch (t) {
            case PR_SYMBOL_TYPE.STRING:
                if (Packrat._strmatch(input, v, pos)) {
                    return PrMatch(v.len(), null)
                } else {
                    return null;
                }

            case PR_SYMBOL_TYPE.RE:
                matching = v.search(input, pos);
                if (!matching) return null;
                assert(matching.begin == pos);
                return PrMatch(matching.end - matching.begin, null);

            case PR_SYMBOL_TYPE.COMPOSITE:
                options = v;
            case PR_SYMBOL_TYPE.NT:
                options = options ||  grammar.rules[v];
                for (local i = 0; i < options.len(); i++) {
                    local option = options[i];
                    local good = true;
                    local submatches = [];
                    local s = pos;
                    assert(typeof option == "array");
                    foreach (sym in option) {
                        assert(sym instanceof PrSymbol);
                        local match = sym.match(input, s, grammar, actions, memos, state);
                        if (match == null) {
                            good = false;
                            break;
                        } else {
                            assert(typeof match.l == "integer");
                            s += match.l;
                            // TODO make this configureable?  Like `actions`?
                            // maybe just have "wrapped" or "unwrapped" as options?
                            _post(sym, match, submatches, grammar);
                        }
                    }
                    if (good) {
                        local m = PrMatch(s - pos, submatches);
                        if (t == PR_SYMBOL_TYPE.NT) m.nt = v;
                        m.alt = i;
                        return m;
                    } else {
                        continue;
                    }
                }
                return null;

            case PR_SYMBOL_TYPE.REPETITION:
                local sym = v.sym;
                assert(sym instanceof PrSymbol);
                local low = v.low;
                local high = v.high;
                local matches = 0;
                local submatches = [];
                local offset = 0;
                while (high == null || matches <= high) {
                    local match = sym.match(input, pos+offset, grammar, actions, memos, state);
                    if (match == null) {
                        break;
                    } else {
                        assert(match instanceof PrMatch);
                        matches += 1;
                        offset += match.l;
                        _post(sym, match, submatches, grammar);
                    }
                }
                if (matches >= low) {
                    local m = PrMatch(offset, submatches);
                    m.n = matches;
                    return m;
                } else {
                    return null;
                }

            case PR_SYMBOL_TYPE.LOOKAHEAD:
                match = v.match(input, pos, grammar, actions, memos, state);
                if (match) {
                    return PrMatch(0, null);
                } else {
                    return null;
                }

            case PR_SYMBOL_TYPE.NEGATIVE_LOOKAHEAD:
                match = v.match(input, pos, grammar, actions, memos, state);
                if (match) {
                    return null;
                } else {
                    return PrMatch(0, null);
                }

            case PR_SYMBOL_TYPE.POSITION_ASSERTION:
                if (v >= 0 ? pos == v : pos == input.len()+1+v) {
                    return PrMatch(0, null);
                } else {
                    return null;
                }

            case PR_SYMBOL_TYPE.BOOLEAN:
                if (v) {
                    return PrMatch(0, null);
                } else {
                    return null;
                }

            default:
                throw "default case";
        }
    }

    // Post-processing (after cache, decides what to add to the parse tree)
    function _post(sym, match, submatches, grammar) {
        assert(match instanceof PrMatch);
        foreach (key in ["l", "t"]) {
            assert(match[key] != null);
        }

        local keep = true;

        if (match.v == PrMatch.DROP) {
            keep = false
        } else if (sym._keep != null) {
            keep = sym._keep;
        } else if (
            [PR_SYMBOL_TYPE.LOOKAHEAD, PR_SYMBOL_TYPE.NEGATIVE_LOOKAHEAD].find(sym.t) != null && !grammar.noDiscardLookaheads
            || sym.t == PR_SYMBOL_TYPE.NT && sym.v in grammar.discarded && grammar.discarded[sym.v]
            || sym.t == PR_SYMBOL_TYPE.STRING && grammar.discardStrings
            || sym.t == PR_SYMBOL_TYPE.RE && grammar.discardRegexps
        ) {
            keep = false;
        }

        if (keep) {
            submatches.push(match);
        }
    }

    static function nt(name) {
        return PrSymbol(PR_SYMBOL_TYPE.NT, name);
    }

    static function re(str) {
        return PrSymbol(PR_SYMBOL_TYPE.RE, regexp("^" + str));
    }

    static function str(str) {
        return PrSymbol(PR_SYMBOL_TYPE.STRING, str);
    }

    static function composite(opts) {
        if (opts.len() == 0) {
            opts = [[]];
        } else if (typeof opts[0] != "array") {
            opts = [opts];
        }
        return PrSymbol(PR_SYMBOL_TYPE.COMPOSITE, opts);
    }

    static function rep(sym, low=0, high=null) {
        return PrSymbol(PR_SYMBOL_TYPE.REPETITION, { sym=sym, low=low, high=high });
    }

    static function la(sym) {
        return PrSymbol(PR_SYMBOL_TYPE.LOOKAHEAD, sym);
    }

    static function nla(sym) {
        return PrSymbol(PR_SYMBOL_TYPE.NEGATIVE_LOOKAHEAD, sym);
    }

    static function start() {
        return PrSymbol(PR_SYMBOL_TYPE.POSITION_ASSERTION, 0);
    }

    static function end() {
        return PrSymbol(PR_SYMBOL_TYPE.POSITION_ASSERTION, -1);
    }

    static function fail() {
        return PrSymbol(PR_SYMBOL_TYPE.BOOLEAN, false);
    }

    static function drop(symbol, drop=true) {
        symbol._keep = !drop;
        return symbol;
    }
}
