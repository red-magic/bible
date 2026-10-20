#!/usr/bin/env perl

use v5.42;
use warnings;

use Encode          qw(FB_CROAK);
use Errno           qw(ENOENT);
use Getopt::Long    qw(GetOptions);
use PerlIO::encoding;
use Pod::Usage      qw(pod2usage);

$PerlIO::encoding::fallback = FB_CROAK;

$SIG{PIPE} = 'DEFAULT';

binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

{ my $p = $0; $0 = $p if utf8::decode($p); }

use constant INDENT             => 4;
use constant VERSE_PREFIX_WIDTH => 3;

sub maybe_decode {
    my ($s) = @_;
    my $copy = $s;
    return $copy if utf8::decode($copy);
    return $s;
}

sub is_blank {
    my ($line) = @_;
    return $line !~ /\S/;
}

sub strip {
    my ($s) = @_;
    return $s =~ s/^\s+|\s+\z//gr;
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
    my $len = 0;

    for my $word (@$words) {
        my $needed = length($word) + (@current ? 1 : 0);
        if ($len + $needed <= $width) {
            push @current, $word;
            $len += $needed;
        } else {
            push @lines, [@current] if @current;
            @current = ($word);
            $len     = length($word);
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

    my $out = '';
    for my $i (0 .. $#$words) {
        $out .= $words->[$i];
        $out .= ' ' x ($base + ($i < $extra ? 1 : 0)) if $i < $gaps;
    }
    return $out;
}

sub render_line {
    my ($words, $width, $last, $justify) = @_;
    if ($justify && !$last && @$words > 1) {
        return justify_words($words, $width);
    }
    return join(' ', @$words);
}

sub emit_centered {
    my ($text, $width) = @_;
    my $usable = $width - INDENT;
    my $pad    = $usable > length($text)
        ? int(($usable - length($text)) / 2)
        : 0;
    say ' ' x (INDENT + $pad), $text;
}

sub emit_verse {
    my ($line, $width, $justify) = @_;
    my ($num, $text) = split(' ', $line, 2);
    my $prefix = sprintf('%*s', VERSE_PREFIX_WIDTH, $num);
    my $avail  = $width - length($prefix) - 1;
    $avail = 1 if $avail < 1;
    my $cont = ' ' x (length($prefix) + 1);

    if (!defined $text || !length $text) {
        say $prefix;
        return;
    }

    my $wrapped = wrap_words([split(' ', $text)], $avail);
    my $last    = $#$wrapped;
    for my $i (0 .. $last) {
        my $lead = $i == 0 ? "$prefix " : $cont;
        say $lead, render_line($wrapped->[$i], $avail, $i == $last, $justify);
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
        say ' ' x INDENT, strip($line);
    }
}

sub format_file {
    my ($fh, $width, $justify) = @_;

    local $/ = undef;
    my $content = <$fh>;
    $content = '' unless defined $content;

    $content =~ s/\r\n?/\n/g;

    my @lines = length($content) ? split(/\n/, $content, -1) : ();
    pop @lines if $content =~ /\n\z/;

    $_ = s/\s+\z//r for @lines;

    for my $i (0 .. $#lines) {
        my $prev_blank = $i == 0       || is_blank($lines[$i - 1]);
        my $next_blank = $i == $#lines || is_blank($lines[$i + 1]);
        emit_line($lines[$i],
                  classify($lines[$i], $prev_blank, $next_blank),
                  $width, $justify);
    }
}

sub parse_arguments {
    my $width      = 60;
    my $no_justify = 0;
    my $help       = 0;

    GetOptions(
        'w|width=i'    => \$width,
        'n|no-justify' => \$no_justify,
        'h|help'       => \$help,
        ) or pod2usage(-exitval => 2, -verbose => 0);

    pod2usage(-exitval => 0, -verbose => 2) if $help;

    pod2usage(-exitval => 0, -verbose => 2, -output => \*STDERR)
        unless @ARGV;

    if ($width < 1) {
        say STDERR "Error: --width must be a positive integer";
        exit 2;
    }

    if (@ARGV > 1) {
        say STDERR "Error: too many arguments (expected one filename)";
        exit 2;
    }

    return ($width, maybe_decode($ARGV[0]), !$no_justify);
}

sub main {
    my ($width, $filename, $justify) = parse_arguments();

    open(my $fh, '<:encoding(UTF-8)', $filename) or do {
        my $err = $!;
        say STDERR $err == ENOENT
            ? "Error: File '$filename' not found"
            : "Error: $err";
        exit 1;
    };

    my $ok  = eval { format_file($fh, $width, $justify); 1 };
    my $err = $@;
    close $fh;

    if (!$ok) {
        $err =~ s/\s+\z//;
        say STDERR "Error: $err";
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

bible_formatter.pl - format Bible text files with proper indentation
and optional full justification

=head1 SYNOPSIS

 bible_formatter.pl [options] I<filename>

 bible_formatter.pl -w 80 txt/kjv.txt
 bible_formatter.pl -w 70 -n txt/syn.txt
 bible_formatter.pl --no-justify txt/syn.txt

=head1 DESCRIPTION

Reads a Bible text file and writes a reformatted version to standard
output. Blank lines are preserved, chapter headings (lines surrounded
by blank lines) are centred, and verse lines (lines beginning with a
digit) are re-indented, wrapped to the requested width, and optionally
fully justified.

Malformed UTF-8 in the input is treated as an error rather than
silently substituted, so the output is always valid UTF-8.

=head1 OPTIONS

=over 4

=item B<-w> I<n>, B<--width> I<n>

Output line width in columns.  Defaults to 60.

=item B<-n>, B<--no-justify>

Disable full justification; wrap text but leave lines ragged-right.

=item B<-h>, B<--help>

Print this help and exit.

=back

=head1 EXIT STATUS

=over 4

=item C<0>

Success, or help was requested.

=item C<1>

The input file could not be read, or an output error occurred.

=item C<2>

Invalid command-line arguments.

=back

=cut
