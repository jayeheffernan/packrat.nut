// TODO documentation
enum SYMBOL_TYPE {
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
enum STATEMENT_TYPE {
    RULE,
    DISCARD_NT,
    DISCARD_STRINGS,
    DISCARD_REGEXPS,
    NO_DISCARD_LOOKAHEADS,
}

class Match {
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

    // TODO make sure that all of these classes print properly
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
                return ::strslice(_in, s, s + l);
            default:
                throw "key not found: " + k;
        }
    }

}

class Memos {
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
            return Memos.NOT_CACHED;
        }
    }
}

// TODO think about blobs and arrays of tokens
// TODO think about using this as a lexer, and doing a lexer/scanner-based JSON parser
// NB when lexing we can reuse memos throughout
// TODO name things
class Symbol {
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
        if (t == SYMBOL_TYPE.NT) {
            local cached = memos.get(v, pos);
            if (cached != Memos.NOT_CACHED) {
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

        if (t == SYMBOL_TYPE.NT && v in actions) {
            // TODO don't do this if the result is about to be dropped?  Think
            // about effect on cache
            match.v = actions[v](match);
        }

        if (t == SYMBOL_TYPE.NT) {
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
            case SYMBOL_TYPE.STRING:
                if (strmatch(input, v, pos)) {
                    return Match(v.len(), null)
                } else {
                    return null;
                }

            case SYMBOL_TYPE.RE:
                matching = v.search(input, pos);
                if (!matching) return null;
                assert(matching.begin == pos);
                return Match(matching.end - matching.begin, null);

            case SYMBOL_TYPE.COMPOSITE:
                options = v;
            case SYMBOL_TYPE.NT:
                options = options ||  grammar.rules[v];
                for (local i = 0; i < options.len(); i++) {
                    local option = options[i];
                    local good = true;
                    local submatches = [];
                    local s = pos;
                    assert(typeof option == "array");
                    foreach (sym in option) {
                        if (!(sym instanceof Symbol)) {
                            print(sym);
                        }
                        assert(sym instanceof Symbol);
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
                assert(sym instanceof Symbol);
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
                        assert(match instanceof Match);
                        matches += 1;
                        offset += match.l;
                        _post(sym, match, submatches, grammar);
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
                match = v.match(input, pos, grammar, actions, memos, state);
                if (match) {
                    return Match(0, null);
                } else {
                    return null;
                }

            case SYMBOL_TYPE.NEGATIVE_LOOKAHEAD:
                match = v.match(input, pos, grammar, actions, memos, state);
                if (match) {
                    return null;
                } else {
                    return Match(0, null);
                }

            case SYMBOL_TYPE.POSITION_ASSERTION:
                if (v >= 0 ? pos == v : pos == input.len()+1+v) {
                    return Match(0, null);
                } else {
                    return null;
                }

            case SYMBOL_TYPE.BOOLEAN:
                if (v) {
                    return Match(0, null);
                } else {
                    return null;
                }

            default:
                throw "default case";
        }
    }

    // Post-processing (after cache, decides what to add to the parse tree)
    function _post(sym, match, submatches, grammar) {
        assert(match instanceof Match);
        foreach (key in ["l", "t"]) {
            assert(match[key] != null);
        }

        local keep = true;

        if (match.v == Match.DROP) {
            keep = false
        } else if (sym._keep != null) {
            keep = sym._keep;
        } else if (
            [SYMBOL_TYPE.LOOKAHEAD, SYMBOL_TYPE.NEGATIVE_LOOKAHEAD].find(sym.t) != null && !grammar.noDiscardLookaheads
            || sym.t == SYMBOL_TYPE.NT && sym.v in grammar.discarded && grammar.discarded[sym.v]
            || sym.t == SYMBOL_TYPE.STRING && grammar.discardStrings
            || sym.t == SYMBOL_TYPE.RE && grammar.discardRegexps
        ) {
            keep = false;
        }

        if (keep) {
            submatches.push(match);
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
        if (opts.len() == 0) {
            opts = [[]];
        } else if (typeof opts[0] != "array") {
            opts = [opts];
        }
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

    static function start() {
        return Symbol(SYMBOL_TYPE.POSITION_ASSERTION, 0);
    }

    static function end() {
        return Symbol(SYMBOL_TYPE.POSITION_ASSERTION, -1);
    }

    static function fail() {
        return Symbol(SYMBOL_TYPE.BOOLEAN, false);
    }
}
// TODO change this binding
F <- Symbol;

// TODO implement drop as a unary minus metamethod on Symbol, then use it to
// simplify grammarGrammar
// extension: implement '-' for "concatenate, and drop this one", '+' for
// "concatenate, and keep this one" and '/' for dividing options "next option".
// These will need to operate between Symbols and arrays of symbols. * is
// probably the best choice.  See if we can bindenv to `Symbol` so that we
// don't have to put `Symbol.`s or `F.`s everywhere.  Make it like a DSL.  If
// we declare our non-terminals we can even pre-instantiate (or use _get
// metamethod on a delegate) in order to enable referecing non-terminals with
// bare identifiers.  If we automatically convert strings with Symbol.str and
// arrays with F.composite we will be balling
// TODO ALSO!  implement chai's expect in Squirrel using this parser!  (or
// maybe an earley parser would be more suited?)  Each chained accessor can add
// the key as a token to an internal array, then calling the chain (_call
// metamethod) can cause it "compile" the tokens to assertions
function drop(symbol, drop=true) {
    symbol._keep = !drop;
    return symbol;
}

class Grammar {
    _rules = null;
    _env = null;
    _compiled = null;

    constructor(nts=null) {
        _rules = [];
        nts = nts || [];
        _env = {
            s=sym,
            r=rule,
            epsilon=::Rule(this),
            m=Symbol.re,
        };
        foreach (nt in nts) {
            _env[nt] <- ::F.nt(nt);
        }
        _compiled = { discarded = {}, rules = {} };
    }

    function discard(...) {
        if (vargv.len() != 1) {
            return discard(vargv);
        } else if (typeof vargv[0] != "array") {
            return discard([vargv[0]]);
        } else {
            foreach (nt in vargv[0]) {
                _compiled.discarded[typeof nt == "string" ? nt : nt.v] <- true;
            }
        }
    }

    function discard_strings() {
        _compiled.discardStrings <- true;
    }

    function discard_regexps () {
        _compiled.discardRegexps <- true;
    }

    function no_discard_lookaheads () {
        _compiled.noDiscardLookaheads <- true;
    }
    function rules(fn) {
        fn.bindenv(this)();
    }

    function _get(idx) {
        if (idx in _env) return _env[idx];
        return this[idx];
    }

    function compile() {
        foreach (rule in _rules) {
            if (!rule._lhs in grammar.rules) rules[rule._lhs] <- [];
            if (rule._lhs in grammar.rules) {
                _compiled.rules[rule._lhs].extend(rule._opts);
            } else {
                _compiled.rules[rule._lhs] <- rule._opts;
            }
        }
        return _compiled;
    }

    static function rule(name) {
        if (name instanceof Symbol) {
            assert(name.t == SYMBOL_TYPE.NT);
            name = name.v;
        }
        assert(typeof name == "string");
        local rule = ::Rule(this);
        rule._lhs = name;
        rule._opts = null;
        _rules.push(rule);
        _env[name] <- ::F.nt(name);
        return rule;
    }

    static function sym(from = null) {
        if (from instanceof ::Rule) {
            return from;
        } else if (from == null) {
            return ::Rule(this);
        } else if (typeof from == "array") {
            return ::Rule(this, [[::F.composite(from)]]);
        } else if (typeof from == "string") {
            return ::Rule(this, [[::F.str(from)]]);
        } else if (from instanceof Symbol) {
            return ::Rule(this, [[from]]);
        } else {
            throw "can't convert: " + typeof from + ": " + from;
        }
    }
}

class Rule {
    _grammar = null;
    _lhs = null;
    _opts = null;

    constructor(grammar, opts = null) {
        _grammar = grammar;
        _opts = opts || [[]];
    }

    function _mul(r) {
        r = _grammar.sym(r);
        assert(r instanceof Rule);
        _opts[_opts.len()-1].extend(r._opts[0]);
        for (local i = 1; i < r._opts.len(); i++) {
            local opt = r._opts[i];
            _opts.push(opt);
        }
        return this;
    }

    function _mod(r) {
        return this * r;
    }

    function _div(r) {
        r = _grammar.sym(r);
        assert(r instanceof Rule);
        if (!_opts) {
            _opts = r._opts;
            return this;
        }
        r._opts.insert(0, []);
        return this * r;
    }

    function _add(r) {
        r = _grammar.sym(r);
        assert(r instanceof Rule);
        if (_opts[0].len() == 0) return this;
        local next = r._opts[0][0];
        if (next._keep == null) {
            next._keep = true;
        }
        return this * r;
    }

    function _unm() {
        if (_opts[0].len() == 0) return this;
        local next = _opts[0][0];
        if (next._keep == null) {
            next._keep = false;
        }
        return this;
    }

    function _sub(r) {
        r = _grammar.sym(r);
        assert(r instanceof Rule);
        return this * (-r);
    }

}

grammar <- Grammar(["b"]);
grammar.rules(function() {
    rule("a") / b * "a" * b;
    discard([a, b]);
    discard_strings();
    discard_regexps();
    no_discard_lookaheads();
});
grammar = grammar.compile();

print(grammar);

return;

local grammarGrammar = { discarded={}, discardStrings=false, discardRegexps=false, rules={
    "grammar": [
        [F.rep(F.nt("statement")), F.nt("whitespace")],
    ],
    "statement": [
        [F.composite([[F.nt("newline")], [F.start(), F.nt("whitespace")] ]), F.composite([ [F.nt("meta")], [ F.nt("rule") ] ])],
    ],
    "meta": [
        [F.str("%"), F.str("discard"), F.nt("break"), F.nt("idList")],
        [F.str("%"), F.str("discard_strings")],
        [F.str("%"), F.str("discard_regexps")],
        [F.str("%"), F.str("no_discard_lookaheads")],
    ],
    "idList": [
        [F.nt("identifier"), F.rep(F.composite([[F.nt("whitespace"), F.str(","), F.nt("whitespace"), F.nt("identifier")]]))],
    ],
    "identifier": [
        [F.rep(F.composite([ [F.nla(F.str("m/")), drop(F.nla(F.str("epsilon"))), F.re("[a-zA-Z0-9_]")] ]), 1)],
    ],
    "arrow": [
        [F.nt("whitespace"), F.str("<-"), F.nt("whitespace")],
    ],
    "rule": [
        [F.nt("identifier"), F.nt("ruleSuffix")],
    ],
    "ruleSuffix": [
        [F.nt("arrow"), F.nt("ruleRhs") ],
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
            F.nla(F.composite([ [F.nt("identifier"), F.nt("arrow")], [F.nt("meta")] ])),
            F.composite([
                    [F.nt("repetition")],
                    [F.nt("normalSymbol")],
            ]),
        ],
    ],
    "normalSymbol": [
        // the first case covers special markup for lookaheads, etc.
        [F.re(@"[+\-&!]"), F.nt("symbol")],
        [F.nt("nonterminal")],
        [F.nt("composite")],
        [F.nt("string")],
        [F.nt("re")],
    ],
    "repetition": [
        // TODO specific number of repetitions?
        [F.nt("normalSymbol"), F.re(@"[?*+]")],
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
    "newline": [
        [F.re(@"\s*\n(\n|\s)*")],
    ],
}};

grammarActions <- {
    "whitespace": @(match) null,
    "chars": @(match) match.v[0].string,
    "string": @(match) F.str(match.v[1].v),
    "nonterminal": @(match) F.nt(match.v[0].v),
    "re": @(match) F.re(match.v[1].string),
    "composite": @(match) F.composite(match.v[1].v),
    "repetition": function(match) {
        assert(typeof match.v == "array");
        assert(match.v.len() == 2);
        assert(match.v[1].v == null)
        local sym = match.v[0].v;
        local repChar = match.v[1].string;
        local times = { "?": [0, 1], "*": [0, null], "+": [1, null] }[repChar];
        return F.rep(sym, times[0], times[1]);
    },
    "symbol": function(match) {
        local composite = match.v[0];
        assert(composite.t != SYMBOL_TYPE.NEGATIVE_LOOKAHEAD);
        assert(typeof composite.v == "array");
        assert(composite.v.len() == 1);
        return composite.v[0].v;
    },
    "normalSymbol": function(match) {
        local sym = match.v[match.v.len()-1].v;
        if (match.alt == 0) {
            return {
                "+": @() drop(sym, false),
                "-": @() drop(sym),
                "&": @() F.la(sym),
                "!": @() F.nla(sym),
            }[match.v[0].string]();
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
    "identifier": @(match) join(match.v[0].v.map(@(sub) sub.v[0].string)),
    "rule": @(match) [STATEMENT_TYPE.RULE, match.v[0].v, match.v[1].v]
    "idList": function(match) {
        local first = match.v[0].v;
        local rest = match.v[1].v.map(@(m) m.v[3].v);
        rest.insert(0, first);
        return rest;
    },
    "meta": function(match) {
        local type = {
            discard               = STATEMENT_TYPE.DISCARD_NT,
            discard_strings       = STATEMENT_TYPE.DISCARD_STRINGS,
            discard_regexps       = STATEMENT_TYPE.DISCARD_REGEXPS,
            no_discard_lookaheads = STATEMENT_TYPE.NO_DISCARD_LOOKAHEADS,
        }[match.v[1].string];
        local info = [type];

        if (match.alt == 0) {
            local ids = match.v[3].v;
            info.push(ids);
        }

        return info;
    },
    "statement": function(match) {
        assert(typeof match.v == "array")
        assert(match.v.len() == 2);
        local composite = match.v[1];
        assert(typeof composite.v == "array")
        assert(composite.v.len() == 1);
        local triplet = composite.v[0].v;
        return triplet;
    }
    "grammar": function(match) {
        local rules = {};
        local grammar = { discarded = {}, rules = {} };
        foreach (sub in match.v[0].v) {
            local statement = sub.v;
            local type = statement[0];
            if (type == STATEMENT_TYPE.RULE) {
                grammar.rules[statement[1]] <- statement[2]
            } else if (type == STATEMENT_TYPE.DISCARD_NT) {
                foreach (id in statement[1]) {
                    grammar.discarded[id] <- true;
                }
            } else if (type == STATEMENT_TYPE.DISCARD_STRINGS) {
                grammar.discardStrings <- true;
            } else if (type == STATEMENT_TYPE.DISCARD_REGEXPS) {
                grammar.discardRegexps <- true;
            } else if (type == STATEMENT_TYPE.NO_DISCARD_LOOKAHEADS) {
                grammar.noDiscardLookaheads <- true;
            } else {
                throw "unexpected";
            }
        }
        return grammar;
    },
};

GRAMMAR_DEFAULTS <- { discarded={}, discardStrings=false, discardRegexps=false, noDiscardLookaheads=false };

function parse(ruleName, input, grammar, actions, printMemos=false) {
    if (typeof grammar == "string") {
        grammar = parse("grammar", grammar, grammarGrammar, grammarActions);
        if (!grammar) {
            throw "bad grammar";
        }
    }

    // make sure flags are available when we go to access them
    grammar.setdelegate(GRAMMAR_DEFAULTS);
    local state = {};

    // Init cache
    local memos = Memos(input.len(), ruleName);

    local start = Symbol.nt(ruleName);
    start.match(input, 0, grammar, actions, memos, state);

    if (printMemos) print(memos._memos[0]);
    local match = memos.get(ruleName, 0);
    if (match == Memos.NOT_CACHED || match.l != input.len()) {
        return null;
    } else {
        return match.v;
    }
}
