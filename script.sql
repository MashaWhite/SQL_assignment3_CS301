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

