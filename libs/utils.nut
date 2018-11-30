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

function mergeAll(tables) {
    local merged = {};
    foreach (t in tables) {
        foreach (k,v in t) {
            merged[k] <- v;
        }
    }
    return merged;
}
