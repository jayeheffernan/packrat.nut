/**
 * JSON encoder
 *
 * @author Mikhail Yurasov <mikhail@electricimp.com>
 * @verion 0.7.0
 */
class JSONEncoder {

  static version = [1, 0, 0];

  // max structure depth
  // anything above probably has a cyclic ref
  static _maxDepth = 32;

  /**
   * Encode value to JSON
   * @param {table|array|*} value
   * @returns {string}
   */
  function encode(value) {
    return this._encode(value);
  }

  /**
   * @param {table|array} val
   * @param {integer=0} depth – current depth level
   * @private
   */
  function _encode(val, depth = 0) {

    // detect cyclic reference
    if (depth > this._maxDepth) {
      throw "Possible cyclic reference";
    }

    local
      r = "",
      s = "",
      i = 0;

    switch (typeof val) {

      case "table":
      case "class":
        s = "";

        // serialize properties, but not functions
        foreach (k, v in val) {
          if (typeof v != "function") {
            s += ",\"" + k + "\":" + this._encode(v, depth + 1);
          }
        }

        s = s.len() > 0 ? s.slice(1) : s;
        r += "{" + s + "}";
        break;

      case "array":
        s = "";

        for (i = 0; i < val.len(); i++) {
          s += "," + this._encode(val[i], depth + 1);
        }

        s = (i > 0) ? s.slice(1) : s;
        r += "[" + s + "]";
        break;

      case "integer":
      case "float":
      case "bool":
        r += val;
        break;

      case "null":
        r += "null";
        break;

      case "instance":

        if ("_serializeRaw" in val && typeof val._serializeRaw == "function") {

            // include value produced by _serializeRaw()
            r += val._serializeRaw().tostring();

        } else if ("_serialize" in val && typeof val._serialize == "function") {

          // serialize instances by calling _serialize method
          r += this._encode(val._serialize(), depth + 1);

        } else {

          s = "";

          try {

            // iterate through instances which implement _nexti meta-method
            foreach (k, v in val) {
              s += ",\"" + k + "\":" + this._encode(v, depth + 1);
            }

          } catch (e) {

            // iterate through instances w/o _nexti
            // serialize properties, but not functions
            foreach (k, v in val.getclass()) {
              if (typeof v != "function") {
                s += ",\"" + k + "\":" + this._encode(val[k], depth + 1);
              }
            }

          }

          s = s.len() > 0 ? s.slice(1) : s;
          r += "{" + s + "}";
        }

        break;

      // strings and all other
      default:
        r += "\"" + this._escape(val.tostring()) + "\"";
        break;
    }

    return r;
  }

  /**
   * Escape strings according to http://www.json.org/ spec
   * @param {string} str
   */
  function _escape(str) {
    local res = "";

    for (local i = 0; i < str.len(); i++) {

      local ch1 = (str[i] & 0xFF);

      if ((ch1 & 0x80) == 0x00) {
        // 7-bit Ascii

        ch1 = format("%c", ch1);

        if (ch1 == "\"") {
          res += "\\\"";
        } else if (ch1 == "\\") {
          res += "\\\\";
        } else if (ch1 == "/") {
          res += "\\/";
        } else if (ch1 == "\b") {
          res += "\\b";
        } else if (ch1 == "\f") {
          res += "\\f";
        } else if (ch1 == "\n") {
          res += "\\n";
        } else if (ch1 == "\r") {
          res += "\\r";
        } else if (ch1 == "\t") {
          res += "\\t";
        } else if (ch1 == "\0") {
          res += "\\u0000";
        } else {
          res += ch1;
        }

      } else {

        if ((ch1 & 0xE0) == 0xC0) {
          // 110xxxxx = 2-byte unicode
          local ch2 = (str[++i] & 0xFF);
          res += format("%c%c", ch1, ch2);
        } else if ((ch1 & 0xF0) == 0xE0) {
          // 1110xxxx = 3-byte unicode
          local ch2 = (str[++i] & 0xFF);
          local ch3 = (str[++i] & 0xFF);
          res += format("%c%c%c", ch1, ch2, ch3);
        } else if ((ch1 & 0xF8) == 0xF0) {
          // 11110xxx = 4 byte unicode
          local ch2 = (str[++i] & 0xFF);
          local ch3 = (str[++i] & 0xFF);
          local ch4 = (str[++i] & 0xFF);
          res += format("%c%c%c%c", ch1, ch2, ch3, ch4);
        }

      }
    }

    return res;
  }
}
/** Class for pretty-printing squirrel objects */
class PrettyPrinter {

    static version = [1, 0, 1];

    _indentStr = null;
    _truncate = null;
    _encode = null;

    /**
     * @param {string} indentStr - String prepended to each line to add one
     * level of indentation (defaults to four spaces)
     * @param {boolean} truncate - Whether or not to truncate long output (can
     * also be set when print is called)
     */
    function constructor(indentStr = null, truncate=true) {
        _indentStr = (indentStr == null) ? "    " : indentStr;
        _truncate = truncate;

        if ("JSONEncoder" in getroottable()) {
            // The JSONEncoder class is available, use it
            _encode = JSONEncoder.encode.bindenv(JSONEncoder);

        } else if (imp.environment() == ENVIRONMENT_AGENT) {
            // We are in the agent, fall back to built in encoder
            _encode = http.jsonencode.bindenv(http);

        } else  {
            throw "Unmet dependency: PrettyPrinter requires JSONEncoder when ran in the device";
        }
    }

    /**
     * Prettifies a squirrel object
     *
     * Functions will NOT be included
     * @param {*} obj - A squirrel object
     * @returns {string} json - A pretty JSON string
     */
    function format(obj) {
        return _prettify(_encode(obj));
    }

    /**
     * Pretty-prints a squirrel object
     *
     * Functions will NOT be included
     * @param {*} obj - Object to print
     * @param {boolean} truncate - Whether to truncate long output (defaults to
     * the instance-level configuration set in the constructor)
     */
    function print(obj, truncate=null) {
        truncate = (truncate == null) ? _truncate : truncate;
        local pretty = this.format(obj);
        (truncate)
            ? server.log(pretty)
            : _forceLog(pretty);
    }

    /**
     * Forceably logs a string to the server by logging one line at a time
     *
     * This circumvents then log's truncation, but messages may still be
     * throttled if string is too long
     * @param {string} string - String to log
     * @param {number max - Maximum number of lines to log
     */
    static function _forceLog(string, max=null) {
        foreach (i, line in split(string, "\n")) {
            if (max != null && i == max) {
                break;
            }
            server.log(line);
        }
    }
    /**
     * Repeats a string a given number of times
     *
     * @returns {string} repeated - a string made of the input string repeated
     * the given number of times
     */
    static function _repeat(string, times) {
        local r = "";
        for (local i = 0; i < times; i++) {
            r += string;
        }
        return r;
    }

    /**
     * Prettifies some JSON
     * @param {string} json - JSON encoded string
     */
    function _prettify(json) {
        local i = 0; // Position in the input string
        local pos = 0; // Current level of indentation
        
        local char = null; // Current character
        local prev = null; // Previous character
        
        local inQuotes = false; // Are we inside a pair of quotes?
        
        local r = ""; // Result string
        
        local len = json.len();
        
        while (i < len) {
            char = json[i];
            
            if (char == '"' && prev != '\\') {
                // End of quoted string
                inQuotes = !inQuotes;
                
            } else if((char == '}' || char == ']') && !inQuotes) {
                // End of an object, dedent
                pos--;
                // Move to the next line and add indentation
                r += "\n" + _repeat(_indentStr, pos);
                
            } else if (char == ' ' && !inQuotes) {
                // Skip any spaces added by the JSON encoder
                i++;
                continue;
                
            }
            
            // Push the current character
            r += char.tochar();
            
            if ((char == ',' || char == '{' || char == '[') && !inQuotes) {
                if (char == '{' || char == '[') {
                    // Start of an object, indent further
                    pos++;
                }
                // Move to the next line and add indentation
                r += "\n" + _repeat(_indentStr, pos);
            } else if (char == ':' && !inQuotes) {
                // Add a space between table keys and values
                r += " ";
            }
     
            prev = char;
            i++;
        }
        
        return r;
    }
}

pp <- PrettyPrinter(null, false);
print <- pp.print.bindenv(pp);
pformat <- pp.format.bindenv(pp);
