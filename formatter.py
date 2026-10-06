import argparse
import os
import signal
import sys
from typing import List, TextIO, Tuple

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

INDENT = 4
VERSE_PREFIX_WIDTH = 3


class BibleFormatter:
    def __init__(self, width: int, justify: bool, indent: int = INDENT) -> None:
        self.width = width
        self.justify = justify
        self.indent = indent

    def format_file(self, file: TextIO) -> None:
        lines = [line.rstrip() for line in file]
        for i, line in enumerate(lines):
            self._emit(line, self._classify(lines, i))

    @staticmethod
    def _classify(lines: List[str], i: int) -> str:
        stripped = lines[i].strip()
        if not stripped:
            return "blank"

        alone = (
            (i == 0 or not lines[i - 1].strip())
            and (i == len(lines) - 1 or not lines[i + 1].strip())
        )
        if alone:
            return "centered"
        if stripped[0].isdigit():
            return "verse"
        return "text"

    def _emit(self, line: str, kind: str) -> None:
        if kind == "blank":
            print()
        elif kind == "centered":
            self._emit_centered(line.strip())
        elif kind == "verse":
            self._emit_verse(line)
        else:
            print(" " * self.indent + line.strip())

    def _emit_centered(self, text: str) -> None:
        usable = max(0, self.width - self.indent)
        padding = max(0, (usable - len(text)) // 2)
        print(" " * (self.indent + padding) + text)

    def _emit_verse(self, line: str) -> None:
        verse_num, text = line.split(maxsplit=1)
        prefix = verse_num.rjust(VERSE_PREFIX_WIDTH)
        avail = max(1, self.width - len(prefix) - 1)
        continuation = " " * (len(prefix) + 1)

        wrapped = self._wrap(text.split(), avail)
        last = len(wrapped) - 1

        for i, words in enumerate(wrapped):
            lead = f"{prefix} " if i == 0 else continuation
            print(lead + self._render(words, avail, last=(i == last)))

    @staticmethod
    def _wrap(words: List[str], width: int) -> List[List[str]]:
        lines: List[List[str]] = []
        current: List[str] = []
        length = 0

        for word in words:
            needed = len(word) + (1 if current else 0)
            if length + needed <= width:
                current.append(word)
                length += needed
            else:
                lines.append(current)
                current, length = [word], len(word)

        if current:
            lines.append(current)
        return lines

    def _render(self, words: List[str], width: int, last: bool) -> str:
        if self.justify and not last and len(words) > 1:
            return self._justify(words, width)
        return " ".join(words)

    @staticmethod
    def _justify(words: List[str], width: int) -> str:
        gaps = len(words) - 1
        base, extra = divmod(width - sum(len(w) for w in words), gaps)

        parts: List[str] = []
        for i, word in enumerate(words):
            parts.append(word)
            if i < gaps:
                parts.append(" " * (base + (1 if i < extra else 0)))
        return "".join(parts)

def parse_arguments() -> Tuple[int, str, bool]:
    parser = argparse.ArgumentParser(
        prog=os.path.basename(sys.argv[0]),
        description="format bible text files with proper indentation and justification",
        epilog=(
            "examples:\n"
            "  %(prog)s txt/kjv.txt\n"
            "  %(prog)s -w 80 txt/kjv.txt\n"
            "  %(prog)s -w 70 -n txt/syn.txt\n"
            "  %(prog)s --no-justify txt/syn.txt"
        ),
        formatter_class=argparse.RawTextHelpFormatter,
    )
    parser.add_argument(
        "-w", "--width", type=int, default=60,
        help="output line width (default: 60)",
    )
    parser.add_argument(
        "-n", "--no-justify", action="store_true",
        help="disable full justification of text",
    )
    parser.add_argument("filename", help="input text file to format")

    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(0)

    args = parser.parse_args()
    return args.width, args.filename, not args.no_justify

def main() -> None:
    width, filename, justify = parse_arguments()
    formatter = BibleFormatter(width, justify)

    try:
        with open(filename, "r", encoding="utf-8") as f:
            formatter.format_file(f)
    except FileNotFoundError:
        sys.exit(f"Error: File '{filename}' not found")
    except Exception as e:
        sys.exit(f"Error: {e}")


if __name__ == "__main__":
    main()
