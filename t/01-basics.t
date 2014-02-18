#!perl

use 5.010;
use strict;
use warnings;
use FindBin '$Bin';

use File::Slurp;
use Finance::Currency::Convert::KlikBCA qw(convert_currency get_currencies);
use Test::More 0.98;

my $page = "$Bin/data/kurs_counter_bca_landing.jsp";

my $res = get_currencies(_page_content => ~~read_file($page));
is($res->[0], 200, "get_currencies() status");
$Finance::Currency::Convert::KlikBCA::_get_res = $res;

is(convert_currency(1, "USD", "IDR"), 11675, "convert_currency() 1");

done_testing;
