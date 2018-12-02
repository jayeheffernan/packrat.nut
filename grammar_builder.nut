class PrGrammarBuilder {
    _rules = null;
    _env = null;
    _compiled = null;

    constructor() {
        _rules = [];
        _env = {
            s=rule,
            epsilon=::PrRule(),
            m=PrSymbol.re,
            nt=PrSymbol.nt,
            START=PrSymbol.start(),
            END=PrSymbol.end(),
        };
        _compiled = { discarded = {}, rules = {}, discardStrings=false, discardRegexps=false, noDiscardLookaheads=false };
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

    // TODO test this
    function declare(...) {
        if (vargv.len() != 1) {
            return discard(vargv);
        } else if (typeof vargv[0] != "array") {
            return discard([vargv[0]]);
        } else {
            foreach (nt in vargv[0]) {
                if (typeof nt == "string") {
                    _env[nt] <- ::PrSymbol.nt(nt);
                } else {
                    _env[nt.v] <- nt;
                }
            }
        }
    }

    static function rep(r, low=0, high=null) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        assert(r._opts.len() == 1);
        assert(r._opts[0].len() == 1);
        return sym(PrSymbol.rep(r._opts[0][0], low, high));
    }

    static function nla(r) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        assert(r._opts.len() == 1);
        assert(r._opts[0].len() == 1);
        return sym(PrSymbol.nla(r._opts[0][0]));
    }

    static function la(r) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        assert(r._opts.len() == 1);
        assert(r._opts[0].len() == 1);
        return sym(PrSymbol.la(r._opts[0][0]));
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
        return this;
    }

    function _get(idx) {
        if (idx in _env) return _env[idx];
        return this[idx];
    }

    function compile() {
        foreach (rule in _rules) {
            if (!rule._lhs in _compiled.rules) rules[rule._lhs] <- [];
            if (rule._lhs in _compiled.rules) {
                _compiled.rules[rule._lhs].extend(rule._opts);
            } else {
                _compiled.rules[rule._lhs] <- rule._opts;
            }
        }
        return _compiled;
    }

    static function rule(name=null) {
        if (name instanceof PrSymbol) {
            assert(name.t == PR_SYMBOL_TYPE.NT);
            name = name.v;
        }
        local rule = ::PrRule();
        rule._lhs = name;
        rule._opts = null;
        if (typeof name == "string") {
            _rules.push(rule);
            _env[name] <- ::PrSymbol.nt(name);
        }
        return rule;
    }

    static function sym(from = null) {
        if (from instanceof ::PrRule) {
            return from;
        } else if (from == null) {
            return ::PrRule();
        } else if (typeof from == "array") {
            assert(from[0] instanceof PrRule);
            return ::PrRule([[::PrSymbol.composite(from[0]._opts)]]);
        } else if (typeof from == "string") {
            return ::PrRule([[::PrSymbol.str(from)]]);
        } else if (from instanceof PrSymbol) {
            return ::PrRule([[from]]);
        } else {
            throw "can't convert: " + typeof from + ": " + from;
        }
    }
}

class PrRule {
    _lhs = null;
    _opts = null;

    constructor(opts = null) {
        _opts = opts || [[]];
    }

    function _mul(r) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        _opts[_opts.len()-1].extend(r._opts[0]);
        for (local i = 1; i < r._opts.len(); i++) {
            local opt = r._opts[i];
            _opts.push(opt);
        }
        return this;
    }

    function _div(r) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        if (!_opts) {
            _opts = r._opts;
            return this;
        }
        r._opts.insert(0, []);
        return this * r;
    }

    function _keepcatenate(r) {
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        if (_opts[0].len() == 0) return this;
        local next = r._opts[0][0];
        if (next._keep == null) {
            next._keep = true;
        }
        return this * r;
    }

    function _add(r) {
        return _keepcatenate(r);
    }

    function _modulo(r) {
        return _keepcatenate(r);
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
        r = PrGrammarBuilder.sym(r);
        assert(r instanceof PrRule);
        return this * (-r);
    }

}

Packrat.buildGrammar <- function(fn=null) {
    assert(typeof fn == "function");
    return PrGrammarBuilder().rules(fn).compile();
};
