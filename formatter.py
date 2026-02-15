import argparse
import signal
import sys

signal.signal(signal.SIGPIPE, signal.SIG_DFL)

INDENT = 4

def parse_arguments():
    parser = argparse.ArgumentParser(
        prog=sys.argv[0].split('/')[-1],
        description="format bible text files with proper indentation and justification",
        epilog=(
            "examples:\n"
            "  %(prog)s txt/kjv.txt\n"
            "  %(prog)s -w 80 txt/kjv.txt\n"
            "  %(prog)s -w 70 -n txt/syn.txt\n"
            "  %(prog)s --no-justify txt/syn.txt"
        ),
        formatter_class=argparse.RawTextHelpFormatter
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

def is_centered_line(lines, idx):
    prev_empty = idx == 0 or not lines[idx - 1].strip()
    next_empty = idx == len(lines) - 1 or not lines[idx + 1].strip()
    return prev_empty and next_empty

def print_centered(text, width):
    clean = text.strip()
    usable_width = max(0, width - INDENT)
    padding = max(0, (usable_width - len(clean)) // 2)
    print(" " * INDENT + " " * padding + clean)

def format_verse_prefix(num):
    return num.rjust(3)

def justify_line(words, width):
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

def wrap_words(words, width):
    lines, current, length = [], [], 0

    for w in words:
        new_len = length + len(w) + (1 if current else 0)
        if new_len <= width:
            current.append(w)
            length = new_len
        else:
            lines.append(current)
            current = [w]
            length = len(w)

    if current:
        lines.append(current)

    return lines

def process_verse(line, width, justify):
    verse_num, text = line.split(maxsplit=1)
    prefix = format_verse_prefix(verse_num)
    avail = max(1, width - len(prefix) - 1)

    lines = wrap_words(text.split(), avail)

    for i, words in enumerate(lines):
        last = (i == len(lines) - 1)
        if justify and not last and len(words) > 1:
            content = justify_line(words, avail)
        else:
            content = " ".join(words)

        if i == 0:
            print(f"{prefix} {content}")
        else:
            print(" " * (len(prefix) + 1) + content)

def format_file(file, width, justify):
    lines = [line.rstrip() for line in file]

    for i, line in enumerate(lines):
        stripped = line.strip()

        if not stripped:
            print()
            continue

        if is_centered_line(lines, i):
            print_centered(line, width)
        elif stripped[0].isdigit():
            process_verse(line, width, justify)
        else:
            print(" " * INDENT + stripped)

def main():
    width, filename, justify = parse_arguments()

    try:
        with open(filename, "r", encoding="utf-8") as f:
            format_file(f, width, justify)
    except FileNotFoundError:
        sys.exit(f"Error: File '{filename}' not found")
    except Exception as e:
        sys.exit(f"Error: {e}")

if __name__ == "__main__":
    main()
