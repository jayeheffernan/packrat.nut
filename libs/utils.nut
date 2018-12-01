// Join an array of things into a string, separated by sep
function join(arr, sep="") {
    if (arr.len() == 0)
        return "";
    local s = "" + arr[0];
    for (local i = 1; i < arr.len(); i++) {
        s += sep + arr[i];
    }
    return s;
}

function printkeys(table) {
    foreach(k,v in table) {
        server.log(k+": " + typeof v);
    }
}

function printkvs(table) {
    foreach(k,v in table) {
        server.log(k+": " + v);
    }
}

function strslice(str, start, end = null) {
    if (start >= str.len() || start == end) {
        return "";
    } else if (end == null) {
        return str.slice(start);
    } else {
        return str.slice(start, end);
    }
}

function strmatch(str, substr, pos=0) {
    local l = substr.len();
    if (pos + l > str.len()) return false;
    for (local i = 0; i < l; i++) {
        if (substr[i] != str[pos+i]) return false;
    }
    return true;
}

function mergeAll(tables) {
    local merged = {};
    foreach (t in tables) {
        foreach (k,v in t) {
            merged[k] <- v;
        }
    }
    return merged;
}
