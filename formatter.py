import argparse
import os
import signal
import sys
from typing import List, Tuple, TextIO

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

INDENT = 4
VERSE_PREFIX_WIDTH = 3

class BibleFormatter:
    def __init__(self, width: int, justify: bool, indent: int = INDENT):
        self.width = width
        self.justify = justify
        self.indent = indent

    def format_file(self, file: TextIO) -> None:
        lines = [line.rstrip() for line in file]
        for line_type, original in self._classify_lines(lines):
            if line_type == "blank":
                print()
            elif line_type == "centered":
                self._print_centered(original)
            elif line_type == "verse":
                self._format_verse(original)
            else:
                self._print_text(original)

    @staticmethod
    def _classify_lines(lines: List[str]) -> List[Tuple[str, str]]:
        typed_lines = []

        for i, line in enumerate(lines):
            stripped = line.strip()
            if not stripped:
                typed_lines.append(("blank", line))
                continue

            prev_empty = i == 0 or not lines[i - 1].strip()
            next_empty = i == len(lines) - 1 or not lines[i + 1].strip()

            if prev_empty and next_empty:
                typed_lines.append(("centered", line))
            elif stripped[0].isdigit():
                typed_lines.append(("verse", line))
            else:
                typed_lines.append(("text", line))

        return typed_lines

    def _print_centered(self, text: str) -> None:
        clean = text.strip()
        usable_width = max(0, self.width - self.indent)
        padding = max(0, (usable_width - len(clean)) // 2)
        print(" " * self.indent + " " * padding + clean)

    def _print_text(self, text: str) -> None:
        print(" " * self.indent + text.strip())

    def _format_verse(self, line: str) -> None:
        verse_num, text = line.split(maxsplit=1)
        prefix = verse_num.rjust(VERSE_PREFIX_WIDTH)
        avail = max(1, self.width - len(prefix) - 1)

        words = text.split()
        wrapped_lines = self._wrap_words(words, avail)

        for i, line_words in enumerate(wrapped_lines):
            last = i == len(wrapped_lines) - 1
            if self.justify and not last and len(line_words) > 1:
                content = self._justify_line(line_words, avail)
            else:
                content = " ".join(line_words)

            if i == 0:
                print(f"{prefix} {content}")
            else:
                print(" " * (len(prefix) + 1) + content)

    @staticmethod
    def _wrap_words(words: List[str], width: int) -> List[List[str]]:
        lines, current, current_len = [], [], 0
        for w in words:
            needed = len(w) + (1 if current else 0)
            if current_len + needed <= width:
                current.append(w)
                current_len += needed
            else:
                lines.append(current)
                current = [w]
                current_len = len(w)
        if current:
            lines.append(current)
        return lines

    @staticmethod
    def _justify_line(words: List[str], width: int) -> str:
        if len(words) == 1:
            return words[0]

        text_len = sum(len(w) for w in words)
        spaces_needed = width - text_len
        gaps = len(words) - 1

        base = spaces_needed // gaps
        extra = spaces_needed % gaps

        parts = []
        for i, w in enumerate(words):
            parts.append(w)
            if i < gaps:
                spaces = base + (1 if i < extra else 0)
                parts.append(" " * spaces)
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

    parser.add_argument("-w", "--width", type=int, default=60,
                        help="output line width (default: 60)")
    parser.add_argument("-n", "--no-justify", action="store_true",
                        help="disable full justification of text")
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
