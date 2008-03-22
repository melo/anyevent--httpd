package BS::HTTPD::Appgets;
use feature ':5.10';
use strict;
no warnings;
use CGI qw/escapeHTML/;

require Exporter;

our @ISA = qw/Exporter/;

our @EXPORT = qw/o alink abutton set_request set_httpd js js_ajaxobj_func capture form entry/;

=head1 NAME

BS::HTTPD::Appgets - Some utility functions for web applications

=head1 EXPORTS

This module mostly exports these functions:

=over 4

=cut

our $REQ;

=item B<set_request ($ref)>

This function sets the current request the output is appended
to for the response.

Use it eg. like this:

   $httpd->reg_cb (
      _ => sub {
         my ($httpd, $req) = @_;
         set_request ($req);

         o "<html><body><h1>test</h1></body></html>";

         $req->respond;
      }
   );

=cut

sub set_request { $REQ = $_[0] }

=item B<capture ($block)>

C<capture> temporarily redirects the output done in C<$block> and returns it.

This function should be called with a block as argument like this:

   my $r = capture {
      o ("<html><body>Hi</body></html>")
   }

The return value will be simply the concationated output as it would be sent to the
callback or appended to the reference given to C<set_output>.

=cut

sub capture(&@) {
   my ($blk) = @_;
   my $old = $REQ;
   my $out;
   $REQ = \$out;
   $blk->();
   $REQ = $old;
   return $out;
}

our $curform;

=item B<o (@strs)>

This function will append all arguments it gets and
append that to the current output context, which is either
set by the C<capture> function or C<set_request>.

If it is called outside a C<capture> function it will just forward
everything to the C<o> method of C<set_request>.

=cut

sub o {
   if (ref $REQ ne 'SCALAR') {
      $REQ->o (join '', @_);
   } else {
      $$REQ .= join '', @_;
   }
}

=item B<form ($block, $callback)>

This function will generate a html form for you, which you can fill
with your own input elements. The C<$callback> will be called when the next
request is handled and if the form was submitted. It will be executed before any
of your content callbacks are run.
The C<form> function has a special prototype which allows this syntax:

   my $new_element;
   form {
      entry (\$new_element);
      o '<input type="submit" value="append"/>'
   } sub {
      push @list, $new_element;
   };

This function is just a convenience wrapper around the C<form> method
of the L<BS::HTTPD> object.

=cut

sub form(&;@) {
   my ($blk, $formcb) = @_;
   $curform = { next_field_idx => 1 };
   my $f = capture { $blk->() };
   my $thisform = $curform;
   $curform = undef;
   my $set_refs = sub {
      my ($req) = @_;

      for (keys %{$thisform->{flds}}) {
         ${$thisform->{flds}->{$_}} = $req->parm ("field$_");
      }

      $formcb->($req);
   };
   o ($REQ->form ($f, $set_refs));
}

=item B<entry ($ref)>

This function will output a text input form field via the C<o> function
which will set the scalar reference to the value of the text field
when the form is submitted.

See also the C<form> function above for an example.

=cut

sub entry {
   my ($ref) = @_;
   my $idx = $curform->{next_field_idx}++;
   $curform->{flds}->{$idx} = $ref;
   o "<input type=\"text\" name=\"field$idx\" value=\"".escapeHTML ($$ref)."\" />";
}

=item B<js (@strs)>

This function will output the C<@strs> appended enclosed in a HTML
script tag for javascript.

See also the C<o> function.

=cut

sub js {
   o ("<script type=\"text/javascript\">\n");
   o (@_);
   o ("</script>\n");
}

=item B<js_ajaxobj_func ($funcname)>

This function will output javascript compatibility cruft code
to get a XMLHttpRequest object. The javascript function C<$funcname>
will be declared and can be called in javascript code with the
content callback as first argument:

   js_ajaxobj_func 'newxhreq';

   js (<<'JS');
      function response_cb (xh, textcontent) {
         ...
      }

      var xh = newxhreq (response_cb);
      xh.open ("GET", "/", true)
      xh.send (null);
   JS

The first argument of the C<response_cb> is the XMLHttpRequest object
and the second the responseText of the finished request.

=cut

sub js_ajaxobj_func {
   my ($funcname) = @_;
   js (<<AJAXFUNC);
function $funcname (content_cb) {
   var xh;

   if( !window.XMLHttpRequest ) XMLHttpRequest = function()
   {
     try{ return new ActiveXObject("Msxml2.XMLHTTP.6.0") }catch(e){}
     try{ return new ActiveXObject("Msxml2.XMLHTTP.3.0") }catch(e){}
     try{ return new ActiveXObject("Msxml2.XMLHTTP") }catch(e){}
     try{ return new ActiveXObject("Microsoft.XMLHTTP") }catch(e){}
     throw new Error("Could not find an XMLHttpRequest alternative.")
   };

   xh = new XMLHttpRequest ();

   xh.onreadystatechange = function () {
      if (xh.readyState == 4 && xh.status == 200) {
         content_cb (xh, xh.responseText);
      }
   };
   return xh;
}
AJAXFUNC
}

=back

=head1 VARIABLES

=over 4

=item B<$BS::HTTPD::Appgets::JSON_JS>

This variable contains the javascript source of the JSON serializer
and deserializer described in L<http://www.JSON.org/js.html>.

You can use this in your application by for example output it via the C<js> function
like this:

   js ($BS::HTTPD::Appgets::JSON_JS);

=back

=cut

our $JSON_JS = <<'JSON_JS_CODE';
/*
    json2.js
    2008-02-14

    Public Domain

    No warranty expressed or implied. Use at your own risk.

    See http://www.JSON.org/js.html

    This file creates a global JSON object containing two methods:

        JSON.stringify(value, whitelist)
            value       any JavaScript value, usually an object or array.

            whitelist   an optional array parameter that determines how object
                        values are stringified.

            This method produces a JSON text from a JavaScript value.
            There are three possible ways to stringify an object, depending
            on the optional whitelist parameter.

            If an object has a toJSON method, then the toJSON() method will be
            called. The value returned from the toJSON method will be
            stringified.

            Otherwise, if the optional whitelist parameter is an array, then
            the elements of the array will be used to select members of the
            object for stringification.

            Otherwise, if there is no whitelist parameter, then all of the
            members of the object will be stringified.

            Values that do not have JSON representaions, such as undefined or
            functions, will not be serialized. Such values in objects will be
            dropped; in arrays will be replaced with null.
            JSON.stringify(undefined) returns undefined. Dates will be
            stringified as quoted ISO dates.

            Example:

            var text = JSON.stringify(['e', {pluribus: 'unum'}]);
            // text is '["e",{"pluribus":"unum"}]'

        JSON.parse(text, filter)
            This method parses a JSON text to produce an object or
            array. It can throw a SyntaxError exception.

            The optional filter parameter is a function that can filter and
            transform the results. It receives each of the keys and values, and
            its return value is used instead of the original value. If it
            returns what it received, then structure is not modified. If it
            returns undefined then the member is deleted.

            Example:

            // Parse the text. If a key contains the string 'date' then
            // convert the value to a date.

            myData = JSON.parse(text, function (key, value) {
                return key.indexOf('date') >= 0 ? new Date(value) : value;
            });

    This is a reference implementation. You are free to copy, modify, or
    redistribute.

    Use your own copy. It is extremely unwise to load third party
    code into your pages.
*/

/*jslint evil: true */

/*global JSON */

/*members "\b", "\t", "\n", "\f", "\r", "\"", JSON, "\\", apply,
    charCodeAt, floor, getUTCDate, getUTCFullYear, getUTCHours,
    getUTCMinutes, getUTCMonth, getUTCSeconds, hasOwnProperty, join, length,
    parse, propertyIsEnumerable, prototype, push, replace, stringify, test,
    toJSON, toString
*/

if (!this.JSON) {

    JSON = function () {

        function f(n) {    // Format integers to have at least two digits.
            return n < 10 ? '0' + n : n;
        }

        Date.prototype.toJSON = function () {

// Eventually, this method will be based on the date.toISOString method.

            return this.getUTCFullYear()   + '-' +
                 f(this.getUTCMonth() + 1) + '-' +
                 f(this.getUTCDate())      + 'T' +
                 f(this.getUTCHours())     + ':' +
                 f(this.getUTCMinutes())   + ':' +
                 f(this.getUTCSeconds())   + 'Z';
        };


        var m = {    // table of character substitutions
            '\b': '\\b',
            '\t': '\\t',
            '\n': '\\n',
            '\f': '\\f',
            '\r': '\\r',
            '"' : '\\"',
            '\\': '\\\\'
        };

        function stringify(value, whitelist) {
            var a,          // The array holding the partial texts.
                i,          // The loop counter.
                k,          // The member key.
                l,          // Length.
                r = /["\\\x00-\x1f\x7f-\x9f]/g,
                v;          // The member value.

            switch (typeof value) {
            case 'string':

// If the string contains no control characters, no quote characters, and no
// backslash characters, then we can safely slap some quotes around it.
// Otherwise we must also replace the offending characters with safe sequences.

                return r.test(value) ?
                    '"' + value.replace(r, function (a) {
                        var c = m[a];
                        if (c) {
                            return c;
                        }
                        c = a.charCodeAt();
                        return '\\u00' + Math.floor(c / 16).toString(16) +
                                                   (c % 16).toString(16);
                    }) + '"' :
                    '"' + value + '"';

            case 'number':

// JSON numbers must be finite. Encode non-finite numbers as null.

                return isFinite(value) ? String(value) : 'null';

            case 'boolean':
            case 'null':
                return String(value);

            case 'object':

// Due to a specification blunder in ECMAScript,
// typeof null is 'object', so watch out for that case.

                if (!value) {
                    return 'null';
                }

// If the object has a toJSON method, call it, and stringify the result.

                if (typeof value.toJSON === 'function') {
                    return stringify(value.toJSON());
                }
                a = [];
                if (typeof value.length === 'number' &&
                        !(value.propertyIsEnumerable('length'))) {

// The object is an array. Stringify every element. Use null as a placeholder
// for non-JSON values.

                    l = value.length;
                    for (i = 0; i < l; i += 1) {
                        a.push(stringify(value[i], whitelist) || 'null');
                    }

// Join all of the elements together and wrap them in brackets.

                    return '[' + a.join(',') + ']';
                }
                if (whitelist) {

// If a whitelist (array of keys) is provided, use it to select the components
// of the object.

                    l = whitelist.length;
                    for (i = 0; i < l; i += 1) {
                        k = whitelist[i];
                        if (typeof k === 'string') {
                            v = stringify(value[k], whitelist);
                            if (v) {
                                a.push(stringify(k) + ':' + v);
                            }
                        }
                    }
                } else {

// Otherwise, iterate through all of the keys in the object.

                    for (k in value) {
                        if (typeof k === 'string') {
                            v = stringify(value[k], whitelist);
                            if (v) {
                                a.push(stringify(k) + ':' + v);
                            }
                        }
                    }
                }

// Join all of the member texts together and wrap them in braces.

                return '{' + a.join(',') + '}';
            }
        }

        return {
            stringify: stringify,
            parse: function (text, filter) {
                var j;

                function walk(k, v) {
                    var i, n;
                    if (v && typeof v === 'object') {
                        for (i in v) {
                            if (Object.prototype.hasOwnProperty.apply(v, [i])) {
                                n = walk(i, v[i]);
                                if (n !== undefined) {
                                    v[i] = n;
                                } else {
                                    delete v[i];
                                }
                            }
                        }
                    }
                    return filter(k, v);
                }


// Parsing happens in three stages. In the first stage, we run the text against
// regular expressions that look for non-JSON patterns. We are especially
// concerned with '()' and 'new' because they can cause invocation, and '='
// because it can cause mutation. But just to be safe, we want to reject all
// unexpected forms.

// We split the first stage into 4 regexp operations in order to work around
// crippling inefficiencies in IE's and Safari's regexp engines. First we
// replace all backslash pairs with '@' (a non-JSON character). Second, we
// replace all simple value tokens with ']' characters. Third, we delete all
// open brackets that follow a colon or comma or that begin the text. Finally,
// we look to see that the remaining characters are only whitespace or ']' or
// ',' or ':' or '{' or '}'. If that is so, then the text is safe for eval.

                if (/^[\],:{}\s]*$/.test(text.replace(/\\./g, '@').
replace(/"[^"\\\n\r]*"|true|false|null|-?\d+(?:\.\d*)?(?:[eE][+\-]?\d+)?/g, ']').
replace(/(?:^|:|,)(?:\s*\[)+/g, ''))) {

// In the second stage we use the eval function to compile the text into a
// JavaScript structure. The '{' operator is subject to a syntactic ambiguity
// in JavaScript: it can begin a block or an object literal. We wrap the text
// in parens to eliminate the ambiguity.

                    j = eval('(' + text + ')');

// In the optional third stage, we recursively walk the new structure, passing
// each name/value pair to a filter function for possible transformation.

                    return typeof filter === 'function' ? walk('', j) : j;
                }

// If the text is not JSON parseable, then a SyntaxError is thrown.

                throw new SyntaxError('parseJSON');
            }
        };
    }();
}
JSON_JS_CODE

1;
