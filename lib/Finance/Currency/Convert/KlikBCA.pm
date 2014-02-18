package Finance::Currency::Convert::KlikBCA;

use 5.010001;
use strict;
use warnings;
use Log::Any '$log';
use LWP::Simple;
use Parse::Number::ID qw(parse_number_id);

# VERSION

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_currencies convert_currency);

our %SPEC;

$SPEC{get_currencies} = {
    summary => 'Extract data from KlikBCA page',
    v => 1.1,
};
sub get_currencies {
    my %args = @_;

    my $page;
    if ($args{_page_content}) {
        $page = $args{_page_content};
    } else {
        $page = get "http://www.bca.co.id/id/biaya-limit/kurs_counter_bca/kurs_counter_bca_landing.jsp"
            or return [500, "Can't retrieve KlikBCA page"];
    }

    $page =~ s!(<table .+? Mata\sUang .+?</table>)!!xs
        or return [500, "Can't scrape Mata Uang table"];
    my $mu_table = $1;
    $page =~ s!(<table .+? e-Rate .+?</table>)!!xs
        or return [500, "Can't scrape e-Rate table"];
    my $er_table = $1;
    $page =~ s!(<table .+? TT \s Counter .+?</table>)!!xs
        or return [500, "Can't scrape TT Counter table"];
    my $ttc_table = $1;
    $page =~ s!(<table .+? Bank \s Notes .+?</table>)!!xs
        or return [500, "Can't scrape e-Rate table"];
    my $bn_table = $1;

    my @items;
    while ($mu_table =~ m!<td[^>]+>([A-Z]{3})</td>!gsx) {
        push @items, { currency => $1 };
    }
    @items or return [500, "Check: no currencies found in Mata Uang Table"];
    my $num_items = @items;
    my $i;

    $i = 0;
    while ($er_table   =~ m{
                               <td[^>]+>([0-9.,]+)</td>\s+
                               <td[^>]+>([0-9.,]+)</td>\s*
                               (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_er}  = parse_number_id(text=>$1);
        $items[$i]{buy_er}   = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [500, "Check: #rows in Mata Uang table != Bank Notes table"];

    $i = 0;
    while ($ttc_table   =~ m{
                                <td[^>]+>([0-9.,]+)</td>\s+
                                <td[^>]+>([0-9.,]+)</td>\s*
                                (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_ttc} = parse_number_id(text=>$1);
        $items[$i]{buy_ttc}  = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [500, "Check: #rows in Mata Uang table != TT Counter table"];

    $i = 0;
    while ($bn_table   =~ m{
                               <td[^>]+>([0-9.,]+)</td>\s+
                               <td[^>]+>([0-9.,]+)</td>\s*
                               (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_bn}  = parse_number_id(text=>$1);
        $items[$i]{buy_bn}   = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [500, "Check: #rows in Mata Uang table != Bank Notes table"];

    my %items;
    for (@items) {
        $items{uc $_->{currency}} = $_;
        delete $_->{currency};
    }
    [200, "OK", {update_date=>undef, currencies=>\%items}];
}

sub convert_currency {
    my ($n, $from, $to) = @_;

    my $res = get_currencies();
    return undef if $res->[0] != 200;
    return undef unless uc($to) eq 'IDR';

    my $c = $res->[2]{currencies}{uc $from} or return undef;
    $n * ($c->{sell_bn} + $c->{buy_bn}) / 2;
}

1;
# ABSTRACT: Convert currencies using KlikBCA

=head1 SYNOPSIS

 use Finance::Currency::Convert::KlikBCA qw(convert_currency);

 printf "1 USD = Rp %.0f\n", convert_currency(1, 'USD', 'IDR');


=head1 TODO

=over 4

=item * Currently can only handle conversion I<to> IDR

=item * Parse last update time

=back

=head1 SEE ALSO

L<http://www.klikbca.com/>

=cut
