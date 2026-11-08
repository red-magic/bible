#!/usr/bin/env perl

use v5.42;
use warnings;

use Encode          qw(FB_CROAK);
use Errno           qw(ENOENT);
use Getopt::Long    qw(GetOptions);
use PerlIO::encoding;
use Pod::Usage      qw(pod2usage);

use constant INDENT             => 4;
use constant VERSE_PREFIX_WIDTH => 3;
use constant DEFAULT_WIDTH      => 70;

$PerlIO::encoding::fallback = FB_CROAK;
$SIG{PIPE} = 'DEFAULT';

binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

{ my $program = $0; $0 = $program if utf8::decode($program); }

my $TEXT_COLUMN = 4;

sub maybe_decode {
    my ($string) = @_;
    my $copy = $string;
    return $copy if utf8::decode($copy);
    return $string;
}

sub is_blank {
    my ($line) = @_;
    return $line !~ /\S/;
}

sub strip {
    my ($string) = @_;
    return $string =~ s/^\s+|\s+\z//gr;
}

sub classify {
    my ($line, $prev_blank, $next_blank) = @_;
    return 'blank'    if is_blank($line);
    return 'centered' if $prev_blank && $next_blank;
    return 'verse'    if $line =~ /\A\s*[0-9]/;
    return 'text';
}

sub wrap_words {
    my ($words, $width) = @_;
    my @lines;
    my @current;
    my $length = 0;

    for my $word (@$words) {
        my $needed = length($word) + (@current ? 1 : 0);
        if ($length + $needed <= $width) {
            push @current, $word;
            $length += $needed;
        } else {
            push @lines, [@current] if @current;
            @current = ($word);
            $length  = length($word);
        }
    }
    push @lines, [@current] if @current;
    return \@lines;
}

sub justify_words {
    my ($words, $width) = @_;
    return $words->[0] if @$words < 2;

    my $gaps     = @$words - 1;
    my $occupied = 0;
    $occupied   += length($_) for @$words;

    my $space = $width - $occupied;
    my $base  = int($space / $gaps);
    my $extra = $space % $gaps;

    my $line = '';
    for my $i (0 .. $#$words) {
        $line .= $words->[$i];
        $line .= ' ' x ($base + ($i < $extra ? 1 : 0)) if $i < $gaps;
    }
    return $line;
}

sub render_line {
    my ($words, $width, $last, $justify) = @_;
    return justify_words($words, $width) if $justify && !$last;
    return join(' ', @$words);
}

sub emit_lead_text {
    my ($lead, $text, $extra_pad) = @_;
    $extra_pad //= 0;

    my $pad = $TEXT_COLUMN - length($lead);
    $pad = 0 if $pad < 0;

    my $line = (' ' x $pad) . $lead . (' ' x $extra_pad) . $text;
    say $line;
}

sub emit_centered {
    my ($text, $width) = @_;
    my $usable = $width - 4;
    $usable = 1 if $usable < 1;
    my $pad = $usable > length($text)
        ? int(($usable - length($text)) / 2)
        : 0;
    emit_lead_text('', $text, $pad);
}

sub emit_verse {
    my ($line, $width, $justify) = @_;
    my ($number, $text) = split(' ', $line, 2);
    my $prefix = sprintf('%*s', VERSE_PREFIX_WIDTH, $number);
    my $avail  = $width - length($prefix) - 1;
    $avail = 1 if $avail < 1;
    my $continuation = ' ' x (length($prefix) + 1);

    if (!defined $text || !length $text) {
        emit_lead_text($prefix, '', 0);
        return;
    }

    my $wrapped = wrap_words([split(' ', $text)], $avail);
    my $last    = $#$wrapped;
    for my $i (0 .. $last) {
        my $lead = $i == 0 ? "$prefix " : $continuation;
        my $body = render_line($wrapped->[$i], $avail, $i == $last, $justify);
        emit_lead_text($lead, $body, 0);
    }
}

sub emit_line {
    my ($line, $kind, $width, $justify) = @_;
    if ($kind eq 'blank') {
        say '';
    } elsif ($kind eq 'centered') {
        emit_centered(strip($line), $width);
    } elsif ($kind eq 'verse') {
        emit_verse($line, $width, $justify);
    } else {
        emit_lead_text(' ' x INDENT, strip($line), 0);
    }
}

sub format_file {
    my ($fh, $width, $justify) = @_;

    local $/ = undef;
    $! = 0;
    my $content = <$fh>;
    if (!defined $content) {
        die "read error: $!" if $!;
        $content = '';
    }

    $content =~ s/\A\x{FEFF}//;
    $content =~ s/\r\n?/\n/g;

    my @lines = length($content) ? split(/\n/, $content, -1) : ();
    pop @lines if $content =~ /\n\z/;

    for my $line (@lines) {
        $line =~ s/\s+\z//;
    }

    for my $i (0 .. $#lines) {
        my $prev_blank = $i == 0       || is_blank($lines[$i - 1]);
        my $next_blank = $i == $#lines || is_blank($lines[$i + 1]);
        emit_line($lines[$i],
                  classify($lines[$i], $prev_blank, $next_blank),
                  $width, $justify);
    }
}

sub _tty_columns {
    my $out = `stty size < /dev/tty 2>/dev/null`;
    return $1 + 0 if defined $out && $out =~ /\A\d+\s+(\d+)/;
    return 0;
}

sub detect_terminal_width {
    my $cols = _tty_columns();
    return $cols if $cols > 0;

    if (defined $ENV{COLUMNS} && $ENV{COLUMNS} =~ /\A(\d+)\z/ && $1 > 0) {
        return $1 + 0;
    }

    return 0;
}

sub parse_arguments {
    my $width      = DEFAULT_WIDTH;
    my $no_justify = 0;
    my $no_center  = 0;
    my $help       = 0;

    GetOptions(
        'w|width=i'    => \$width,
        'n|no-justify' => \$no_justify,
        'C|no-center'  => \$no_center,
        'h|help'       => \$help,
        ) or pod2usage(-exitval => 2, -verbose => 0, -output => \*STDERR);

    pod2usage(-exitval => 0, -verbose => 2, -output => \*STDOUT) if $help;

    pod2usage(-exitval => 2, -verbose => 0, -output => \*STDERR)
        unless @ARGV;

    if ($width < 1) {
        say STDERR "Error: --width must be a positive integer";
        exit 2;
    }

    if (@ARGV > 1) {
        say STDERR "Error: too many arguments (expected one filename)";
        exit 2;
    }

    return ($width, maybe_decode($ARGV[0]), !$no_justify, $no_center);
}

sub main {
    my ($width, $filename, $justify, $no_center) = parse_arguments();

    my $term_width = detect_terminal_width();

    my $effective_width = $width;
    if ($term_width > 0) {
        my $max_width = $term_width - 4;
        $max_width = 5 if $max_width < 5;
        if ($effective_width > $max_width) {
            $effective_width = $max_width;
        }
    }
    $effective_width = 5 if $effective_width < 5;

    my $w_text = $effective_width - 4;
    $w_text = 1 if $w_text < 1;

    if (!$no_center && $term_width > 0) {
        my $ideal = int(($term_width - $w_text) / 2);
        $TEXT_COLUMN = $ideal > 4 ? $ideal : 4;
    } else {
        $TEXT_COLUMN = 4;
    }

    open(my $fh, '<:encoding(UTF-8)', $filename) or do {
        my $err = $!;
        my $message = $err == ENOENT
            ? "Error: File '$filename' not found"
            : "Error: $err";
        say STDERR $message;
        exit 1;
    };

    my $ok = eval { format_file($fh, $effective_width, $justify); 1 };
    my $err = $@;
    my $close_ok = close $fh;

    if (!$ok) {
        $err =~ s/\s+\z//;
        say STDERR "Error: $err";
        exit 1;
    }

    if (!$close_ok) {
        say STDERR "Error: failed to close input: $!";
        exit 1;
    }

    close(STDOUT) or do {
        say STDERR "Error: failed to flush standard output: $!";
        exit 1;
    };
}

main();

__END__

=head1 NAME

formatter.pl - format Bible text files with proper indentation and
optional full justification

=head1 SYNOPSIS

 formatter.pl [options] <filename>

 formatter.pl -w 80 txt/kjv.txt
 formatter.pl -w 70 -n txt/syn.txt
 formatter.pl --no-justify txt/syn.txt
 formatter.pl --no-center txt/kjv.txt

=head1 DESCRIPTION

Reads a Bible text file and writes a reformatted version to standard
output. Blank lines are preserved, chapter headings (lines surrounded
by blank lines) are centred, and verse lines (lines beginning with a
digit) are re-indented, wrapped to the requested width, and optionally
fully justified. Trailing whitespace on each line is discarded, and
CRLF or CR line endings are normalised to LF.

The width given with C<--width> is the total width of the verse area,
including the four columns occupied by the verse number and the space
after it. The remaining width is available for the verse text itself.

When a controlling terminal is available, the verse-body column is
horizontally centred within the terminal, while verse numbers hang to
its left. Chapter headings are centred against the verse-body width
(the verse-number prefix is not counted). If C<--width> exceeds the
terminal width (minus 4 columns), it is silently reduced so output
never overflows and always leaves at least 4 spaces on the right. Use
C<--no-center> to disable terminal centring.

Input is decoded as UTF-8. A leading UTF-8 byte-order mark, if
present, is removed. Malformed UTF-8 in the input is treated as an
error rather than silently substituted, so the output is always valid
UTF-8.

=head1 OPTIONS

=over 4

=item B<-w> I<n>, B<--width> I<n>

Total content width in columns, including the verse-number prefix.
Defaults to 70. If the terminal is narrower, the value is clamped to
the terminal width minus 4, leaving a right margin.

=item B<-n>, B<--no-justify>

Disable full justification; wrap text but leave lines ragged-right.

=item B<-C>, B<--no-center>

Do not centre the output within the terminal width. The layout starts
at column 0 as a traditional left-aligned book.

=item B<-h>, B<--help>

Print this help and exit.

=back

=head1 EXIT STATUS

=over 4

=item C<0>

Success, or help was requested.

=item C<1>

The input file could not be opened, read, or closed, or an output
error occurred.

=item C<2>

Invalid command-line arguments.

=back

=cut
