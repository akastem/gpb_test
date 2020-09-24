#!/usr/bin/perl

=commet
Если я всё верно понял по задаче, то предварительно опишу, что и почему реализуется.
Подобный лог уже видел, похоже, что это лог почтового сервера exim.

В следствии чего, добавил пояснения:
- Письмо может иметь одного отправителя и несколько получателей (доставок).
- Жизненный цикл письма возможно отследить по внутреннему ID.
- Прибытие сообщение от адресата "<>" можно пропускать, т.к. это ошибка в формате заголовка From, который не удалось разобрать.
- Доставку в :blackhole:, /dev/null, ... можно пропускать, т.к. это отказ в доставке.
- Все сообщения, которые не имеют флага, являются системными, которые можно пропустить, т.к. нас интересует жизненный цикл доставки для конкретного получателя.

Исходя из вышесказанного, при разборе лога нас интересуют только записи, которые содержат флаг и адрес.

При выводе информации о конкретном получателе может быть полезной следующая информация:
- Прибытие сообщения (запись с отправителем). Получить это сообщение можно по внутреннему ID, т.к. прибытие одно, а доставок может быть несколько.
- Все записи, которые имеют некоторый статус (флаг) жизненного цикла доставки для конкретного получателя.
=cut

use 5.010;
use strict;
use warnings;

use autodie;
use open qw/:encoding(UTF-8) :std/;

use Config::Tiny;
use DBI;

open(my $FH, '<', $ARGV[0]); # autodie

use constant {
	CONFIG => Config::Tiny->read('config'),
	LIMIT  => 100
};

my $dbh = DBI->connect(
	CONFIG->{mysql}->{dsn}, 
	CONFIG->{mysql}->{user},
	CONFIG->{mysql}->{password}
) or die 'Error connecting to database :(';

# Чтоб не много облегчить работу с БД и не дёргать на каждую запись, вставляется пачками по LIMIT штук
# При необходимости более высокой скорости и возможности повысить нагрузку на БД, можно добавить неблокирующие записи
#
sub insert_pack {
	my ($table, $temp, $to_add) = @_;

	my @values;
	my $placeholder = join ",", map { push(@values, @$_); $temp } @$to_add;

	$dbh->do("INSERT INTO `message` (`created`, `id`, `int_id`, `str`) VALUES $placeholder", {}, @values)
		if $table eq 'message';

	$dbh->do("INSERT INTO `log` (`created`, `int_id`, `str`, `address`) VALUES $placeholder", {}, @values)
		if $table eq 'log';
}

my (@to_add_massage, @to_add_log);

while (readline $FH) {
	chomp;

	# Регулярное выражения для определения/валидации полей
	# Для email простое регулярное выражение >
	# > т.к. если адрес в логе, то он уже проверен и составлять по RFC тут не требуется
	#
	my $re_datetime = qr/\d{4}\-\d{2}-\d{2}\s\d{2}\:\d{2}\:\d{2}/;        # Дата и время
	my $re_id       = qr/[a-zA-Z0-9]{6}\-[a-zA-Z0-9]{6}\-[a-zA-Z0-9]{2}/; # Внутренний ID
	my $re_flag     = qr/\<\=|\=\>|\-\>|\*\*|\=\=/;                       # Флаг
	my $re_address  = qr/[\w\-\.]+@([\w\-]+\.)+[\w\-]{2,4}/;              # Email address

	if (
		my ($created, $str, $int_id, $flag, $address) =
			/^($re_datetime)\s(($re_id)\s($re_flag)\s($re_address)\s.*)$/
	) {
		if ($flag eq '<=') {
			my ($id) = $str =~ /id\=(.*)/;
			push(@to_add_massage, [$created, $id, $int_id, $str]);
		}
		else {
			push(@to_add_log, [$created, $int_id, $str, $address]);
		}
	}

	if (@to_add_massage > LIMIT || eof) {
		insert_pack('message', '(?,?,?,?)', \@to_add_massage);
		undef @to_add_massage;
	}

	if (@to_add_log > LIMIT || eof) {
		insert_pack('log', '(?,?,?,?)', \@to_add_log);
		undef @to_add_log;
	}
}

close($FH)