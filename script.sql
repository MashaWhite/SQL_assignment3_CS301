create database pa3;

drop table if exists customers cascade;
drop table if exists products cascade;
drop table if exists orders cascade;
drop table if exists order_items cascade;
drop table if exists order_log;

create table customers (
    customer_id serial primary key,
    full_name varchar(100) not null,
    email varchar(100) unique not null,
    balance numeric(10,2) default 0
);

create table products (
    product_id serial primary key,
    product_name varchar(100) not null,
    price numeric(10,2) not null,
    stock_quantity int not null
);

create table orders (
    order_id serial primary key,
    customer_id int references customers(customer_id),
    order_date timestamp default current_timestamp,
    total_amount numeric(10,2) default 0
);

create table order_items (
    order_item_id serial primary key,
    order_id int references orders(order_id),
    product_id int references products(product_id),
    quantity int not null,
    price numeric(10,2) not null
);

create table order_log (
    log_id serial primary key,
    order_id int,
    customer_id int,
    action varchar(50),
    log_date timestamp default current_timestamp
);

--функція, що рахує загальну суму замовлення
create or replace function calculate_order_total(p_order_id int)
returns numeric
language sql
as $$
--coalesce повертає 0, якщо такого замовлення не існує
--загальна сума = ціна*кількість
    select coalesce(sum(price*quantity), 0) as order_total
	from order_items 
	where order_id = p_order_id
$$;

--процедура для створення замовлення для користувача з заданим id
create or replace procedure create_order(p_customer_id int)
language sql
as $$
--по дефолту значення дати це поточна дата, а ціна 0 - так як потрібно
--тому в ці поля нічого не вставляємо
    insert into orders(customer_id)
    select customer_id from customers where customer_id = p_customer_id
$$;


--процедура для додавання продукту до існуючого замовлення
create or replace procedure add_product_to_order(
    p_order_id int,
    p_product_id int,
    p_quantity int
    )
language sql
as $$
--створила cte(порада ші), щоб зберегти звідти product_id - якщо його не існує, то буде null і нічого не виконається
    with new_data as(
    --вставляю дані в order_items
        insert into order_items(order_id, product_id, quantity, price)
        select p_order_id, product_id, p_quantity, price
        from products
    --перевірка умов: product_id існує, потрібна кількість товару є, потрібна кількість  > 0
        where (product_id = p_product_id) and (stock_quantity >= p_quantity) and (p_quantity > 0)
        returning product_id
    )
--оновлюю інфорамцію про кількість товару
    update products
    set stock_quantity = stock_quantity - p_quantity
    where product_id = (select product_id from new_data)
$$;

--функція розрахунку коректної загальної суми замовлення для tigger
--тут я вже почала використовувати plpgsql, тому що тут легше через умови зробити
create or replace function update_order_total()
returns trigger
language plpgsql
as $$
declare
	correct_order_id int;
begin
	--tg_op відповідає за те, яка саме причина була у виклику цього tigger
	--new повертає old повертає
	--якщо delete, то потрібно викликати old, тому що new є null
	--якщо update або insert,то new
	if TG_OP = 'DELETE' then 
		correct_order_id := old.order_id;
	else 
		correct_order_id := new.order_id;
	end if;

	--оновлення total_amount
	update orders
	set total_amount = calculate_order_total(correct_order_id)
	where order_id = correct_order_id;
	
	--функція повинна повертати тип tigger
	if TG_OP = 'DELETE' then 
		return old;
	else 
		return new;
	end if;
end;	
$$;
--trigger, що оновлює суму замовлення, коли додають, видаляюьб або змінюють дані
create trigger udate_order_total
--для зміни, вставки, видалення
after update or insert or delete on order_items
for each row
--trigger повинен викликати функцію, що повертає тип tigger
execute function update_order_total();


--функція для trigger, що записує логи при створенні нового order
create or replace function log_order_created()
returns trigger
language plpgsql
as $$
begin
	--вставляємо новий запис в order_log
	--використовуємо new, тому що це tigger для insert
	insert into order_log(order_id, customer_id, action, log_date)
	values(new.order_id, new.customer_id, 'new order created', current_timestamp);
	return new;
end;	
$$;
--сам trigger
create trigger log_order_created
--срацбовує після insert
after insert on orders
for each row
execute function log_order_created();


-----------------тестування-------------
--1.створення customer
insert into customers(full_name, email, balance) values('Alice Taylor', 'ataylor@gamil.com', 5000.00);
--перевірка
select * from customers;
--2.сворення product
insert into products(product_name, price, stock_quantity) values('Phone', 200.00, 50);
--перевірка
select * from products;

--3.поцедура додавання orders
--вивести всі замовлення
select * from orders;
--додати нове замовлення для користувача з id=1
call create_order(1);
--превірка, що замовлення додалось
select * from orders;

--4.поцедура додавання product до orders
--вивести всі продукти замовлення з id=1
select * from order_items where order_id = 1;
--додати продукт до замовлення(id продукту=1, категорія 1, кількість 1, ціна розраховується сама)
call add_product_to_order(1, 1, 1);
--перевірка
select * from order_items where order_id = 1;

--5-6.загальна сума замовлення та кількість товару автоматично оновлюються

-----1) при insert
-----вивести total_amount для order з id=1 та калькість products з id=1
select 
	(select total_amount from orders where order_id = 1),
	(select stock_quantity from products where product_id = 1);
-----додати продукт до замовлення
call add_product_to_order(1, 1, 1);
-----перевірити, чи змінилось total_amount та stock_quantity
select 
	(select total_amount from orders where order_id = 1),
	(select stock_quantity from products where product_id = 1);

-----2) при update
select total_amount from orders where order_id = 2;
-----оновити всі ціни для продуктів з order з id = 2
update order_items
	set price = 10 
	where order_id = 2
select total_amount from orders where order_id = 2;

----3) при delete
select * from order_items;
select total_amount from orders where order_id = 1;
delete from order_items where order_id = 1;
select total_amount from orders where order_id = 1;
--але при update і delete на прикладі total_amount оновиться тільки при першому виконанні


--6.
--вивести всі наявні логи
select * from order_log;
--вставити нові дані в orders
insert into orders(customer_id) values (1);
--перевірити зміни в логах
select * from order_log;
-----------------------------------------------------------------------

--query analysis
explain analyze
select
    oi.order_id,
    p.product_name,
    oi.quantity,
    oi.price,
    oi.quantity * oi.price as item_total
from order_items oi
join products p on oi.product_id = p.product_id
where oi.order_id = 2;
