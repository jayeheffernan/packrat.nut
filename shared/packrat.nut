enum FRAGMENT_TYPE {
    NT,
    STRING,
    RE,
    COMPOSITE,
    LOOKAHEAD,
    NEGATIVE_LOOKAHEAD,
    REPETITION
};

class Fragment {
    _fragment = true;
    kind = null;
    value = null;

    constructor(kind_, value_) {
        kind  = kind_;
        value = value_;
    }

    function match(input, pos, rules, memos, actions = {}, post = {}) {
        if (kind == FRAGMENT_TYPE.NT && value in memos[pos]) {
            return memos[pos][value];
        }
        local match = _match(input, pos, rules, memos, actions, post);
        local result;
        if (match == null) {
            return null;
        } else {
            if (typeof match == "integer") {
                local consumed = match;
                result = { consumed=consumed, value=consumed == 0 ? "" : input.slice(pos, pos+consumed) };
            } else {
                assert("value" in match);
                assert("consumed" in match);
                assert(typeof match.consumed == "integer")
                result = match;
            }
        }
        result.kind <- kind;
        result.start <- pos;

        if (kind == FRAGMENT_TYPE.NT) {
            result.name <- value;
            if (value in actions) {
                result.value <- actions[value](result);
            }
        }

        if (kind == FRAGMENT_TYPE.NT) {
            memos[pos][value] <- result;
        }
        assert("value" in result);
        assert("consumed" in result);
        assert(typeof result.consumed == "integer");
        return result;
    }

    function _match(input, pos, rules, memos, actions, post) {
        local string = pos == input.len() ? "" : input.slice(pos);
        local matching, match, total, ruleName, options;
        switch (kind) {
            case FRAGMENT_TYPE.STRING:
                return (value == "" || string.find(value) == 0) ? value.len() : null;

            case FRAGMENT_TYPE.RE:
                matching = regexp(value).search(string, 0);
                if (!matching) {
                    return null;
                }
                return matching.end - matching.begin;

            case FRAGMENT_TYPE.COMPOSITE:
                options = value;
            case FRAGMENT_TYPE.NT:
                options = options || rules[value];
                for (local i = 0; i < options.len(); i++) {
                    local option = options[i];
                    local good = true;
                    local submatches = [];
                    local start = pos;
                    foreach (fragment in option) {
                        local match = fragment.match(input, start, rules, memos, actions);
                        if (match == null) {
                            good = false;
                            break;
                        } else {
                            local consumed = match.consumed;
                            assert(typeof consumed == "integer");
                            // TODO make this configureable?  Like `actions`?
                            submatches.push(_post(match));
                            start += consumed;
                        }
                    }
                    if (good) {
                        local ans = { consumed=start - pos, value=submatches, alternative=i };
                        return ans;
                    } else {
                        continue;
                    }
                }
                return null;

            case FRAGMENT_TYPE.REPETITION:
                local fragment = value.fragment;
                local low = value.low;
                local high = value.high;
                local matches = 0;
                local submatches = [];
                local offset = 0;
                while (high == null || matches <= high) {
                    local match = fragment.match(input, pos+offset, rules, memos, actions);
                    if (match == null) {
                        break;
                    } else {
                        assert(typeof match == "table");
                        assert("consumed" in match);
                        assert(typeof match.consumed == "integer");
                        matches += 1;
                        offset += match.consumed;
                        submatches.push(match);
                    }
                }
                if (matches >= low) {
                    return { consumed=offset, value=submatches, times=matches };
                } else {
                    return null;
                }

            case FRAGMENT_TYPE.LOOKAHEAD:
                match = value.match(input, pos, rules, memos, actions);
                if (match) {
                    // TODO is this good enough?  How to do it in Squirrel?  We don't want this value being modified accidentally
                    local result = clone(match);
                    result.consumed <- 0;
                    result.value <- [];
                    return result;
                } else {
                    return null;
                }

            case FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD:
                match = value.match(input, pos, rules, memos, actions);
                if (match) {
                    return null;
                } else {
                    local result = { name=value.value, consumed=0, value=[] };
                    return result;
                }

            default:
                throw "default case";
        }
    }

    // Post-processing (after cache, before adding to parse tree)
    // TODO we should have this take the match and the array of submatches to be inserted into
    // that way we can drop values (e.g. for lookaheads)
    function _post(match) {
        assert(typeof match == "table");
        foreach (key in ["consumed", "kind", "value"]) {
            assert(key in match);
        }
        if ([FRAGMENT_TYPE.STRING, FRAGMENT_TYPE.RE].find(match.kind) != null) {
            return match.value;
        } else if ([FRAGMENT_TYPE.LOOKAHEAD, FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD].find(match.kind) != null) {
            return null;
        } else {
            return match;
        }
    }

    static function nt(name) {
        return Fragment(FRAGMENT_TYPE.NT, name);
    }

    static function re(str) {
        return Fragment(FRAGMENT_TYPE.RE, "^" + str);
    }

    static function str(str) {
        return Fragment(FRAGMENT_TYPE.STRING, str);
    }

    static function composite(opts) {
        return Fragment(FRAGMENT_TYPE.COMPOSITE, opts);
    }

    static function rep(fragment, low=0, high=null) {
        return Fragment(FRAGMENT_TYPE.REPETITION, { fragment=fragment, low=low, high=high });
    }

    static function la(fragment) {
        return Fragment(FRAGMENT_TYPE.LOOKAHEAD, fragment);
    }

    static function nla(fragment) {
        return Fragment(FRAGMENT_TYPE.NEGATIVE_LOOKAHEAD, fragment);
    }
}
local F = Fragment;

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
        [F.nt("fragment"), F.nt("ruleOptionSuffix")],
    ],
    "ruleOptionSuffix": [
        [F.nt("break"), F.nt("fragment"), F.nt("ruleOptionSuffix")],
        [],
    ],
    "fragment": [
        [
            F.nla(F.composite([ [F.nt("identifier"), F.nt("arrow")] ])),
            F.composite([
                [F.nt("repetition")],
                [F.nt("normalFragment")],
            ]),
        ],
    ],
    "normalFragment": [
        [F.str("!"), F.nt("fragment")],
        [F.str("&"), F.nt("fragment")],
        [F.nt("nonterminal")],
        [F.nt("composite")],
        [F.nt("string")],
        [F.nt("re")],
    ],
    "repetition": [
        [F.nt("normalFragment"), F.composite([[F.str("?")], [F.str("*")], [F.str("+")]])],
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
    "chars": @(match) match.value[0],
    "string": @(match) F.str(match.value[1].value),
    "nonterminal": @(match) F.nt(match.value[0].value),
    "re": @(match) F.re(match.value[1]),
    "composite": @(match) F.composite(match.value[1].value),
    "repetition": function(match) {
        assert(typeof match.value == "array");
        assert(match.value.len() == 2);
        assert(typeof match.value[1].value == "array")
        assert(match.value[1].value.len() == 1)
        local fragment = match.value[0].value;
        local repChar = match.value[1].value[0];
        local times = { "?": [0, 1], "*": [0, null], "+": [1, null] }[repChar];
        return F.rep(fragment, times[0], times[1]);
    },
    "fragment": function(match) {
        local composite = match.value[1];
        assert(typeof composite.value == "array");
        assert(composite.value.len() == 1);
        return composite.value[0].value;
    },
    "normalFragment": function(match) {
        local fragment = match.value[match.value.len()-1].value;
        if (match.alternative == 0) {
            return F.nla(fragment);
        } else if (match.alternative == 1) {
            return F.la(fragment);
        } else {
            return fragment;
        }
    },
    "ruleOption": function(match) {
        if (match.alternative == 0) {
            return [];
        } else {
            local fragment = match.value[0].value;
            local rest = match.value[1].value;
            rest.insert(0, fragment);
            return rest;
        }
    },
    "ruleOptionSuffix": function(match) {
        switch (match.alternative) {
            case 0:
                local fragment = match.value[1].value;
                local rest = match.value[2].value;
                rest.insert(0, fragment);
                return rest;
            case 1:
                return [];
            default:
                throw "unexpected";
        }
    },
    "ruleRhs": function(match) {
        local ruleOption = match.value[0].value;
        local rest = match.value[1].value;
        rest.insert(0, ruleOption);
        return rest;
    },
    "ruleRhsSuffix": function(match) {
        switch (match.alternative) {
            case 0:
                return match.value[3].value;
            case 1:
                return [];
            default:
                throw "unexpected";
        }
    },
    "ruleSuffix": @(match) match.value[1].value,
    "identifier": @(match) join(match.value[0].value.map(@(sub) sub.value[1])),
    "rule": function(match) {
        local result = {};
        result[match.value[0].value] <- match.value[1].value;
        return result;
    },
    "grammar": @(match) mergeAll(match.value[1].value.map(@(submatch) submatch.value)),
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

    local start = Fragment.nt(ruleName);
    start.match(input, 0, rules, memos, actions);

    if (printMemos) print(memos[0]);
    local match = ruleName in memos[0] ? memos[0][ruleName] : null;
    if (match && match.consumed == input.len()) {
        return match.value;
    } else {
        return null;
    }
}
