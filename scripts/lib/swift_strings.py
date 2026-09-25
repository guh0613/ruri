"""Small Swift string/comment lexer for localization audits (not a Swift parser)."""
import re

class Scanner:

    def __init__(self, s):
        self.s = s

    def comment(self, i):
        s = self.s
        if s.startswith('//', i):
            end = s.find('\n', i)
            return len(s) if end < 0 else end
        if s.startswith('/*', i):
            depth = 1
            i += 2
            while i < len(s) and depth:
                if s.startswith('/*', i):
                    depth += 1
                    i += 2
                elif s.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
            return i
        return None

    def start(self, i):
        m = re.match('(#{0,3})("""|")', self.s[i:])
        return (m.group(1), m.group(2)) if m else None

    def expression(self, i):
        start = i
        depth = 1
        s = self.s
        while i < len(s):
            c = self.comment(i)
            if c is not None:
                i = c
                continue
            if self.start(i):
                i = self.string(i)['end']
                continue
            if s[i] == '(':
                depth += 1
            if s[i] == ')':
                depth -= 1
                if depth == 0:
                    return (start, i, i + 1)
            i += 1
        raise ValueError('Unclosed expression')

    def string(self, i):
        s = self.s
        start = i
        hashes, quote = self.start(i)
        i += len(hashes) + len(quote)
        textstart = i
        parts = []
        while i < len(s):
            if s.startswith(quote + hashes, i):
                parts.append(('text', textstart, i))
                return dict(start=start, end=i + len(quote) + len(hashes), parts=parts, hashes=hashes, quote=quote)
            if s.startswith('\\' + hashes + '(', i):
                parts.append(('text', textstart, i))
                begin, end, i = self.expression(i + len(hashes) + 2)
                parts.append(('expr', begin, end))
                textstart = i
                continue
            if s.startswith('\\' + hashes, i):
                i += len(hashes) + 2
            else:
                i += 1
        raise ValueError('Unclosed string ' + s[start:start + 100])

    def nodes(self, start=0, end=None):
        end = len(self.s) if end is None else end
        i = start
        while i < end:
            c = self.comment(i)
            if c is not None:
                i = c
                continue
            if self.start(i):
                n = self.string(i)
                yield n
                i = n['end']
            else:
                i += 1
