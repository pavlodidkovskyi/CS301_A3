-- створ табл
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

-- функція суми замовлення
create or replace function calculate_order_total(p_order_id int)
returns numeric(10,2) as $$
declare
    total_sum numeric(10,2);
begin
    select coalesce(sum(quantity * price), 0)
    into total_sum
    from order_items
    where order_id = p_order_id;

    return total_sum;
end;
$$ language plpgsql;

-- процедур створ нового замовлення
create or replace procedure create_order(p_customer_id int)
language plpgsql
as $$
begin
    if not exists (select 1 from customers where customer_id = p_customer_id) then
        raise notice 'customer not found';
        return;
    end if;

    insert into orders (customer_id, order_date, total_amount)
    values (p_customer_id, current_timestamp, 0);
end;
$$;

-- процедур додав товару в замовлення
create or replace procedure add_product_to_order(
    p_order_id int,
    p_product_id int,
    p_quantity int
)
language plpgsql
as $$
declare
    v_price numeric(10,2);
    v_stock int;
begin
    -- перевір кільк
    if p_quantity <= 0 then
        raise notice 'quantity must be positive';
        return;
    end if;

    -- ціна і залишок
    select price, stock_quantity into v_price, v_stock
    from products
    where product_id = p_product_id;

    -- якщо товару немає
    if v_price is null then
        raise notice 'product not found';
        return;
    end if;

    -- якщо не вистачає на складі
    if v_stock < p_quantity then
        raise notice 'not enough stock';
        return;
    end if;

    -- + товар у замовлення
    insert into order_items (order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, v_price);

    -- онов склад
    update products
    set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;
$$;

-- тригер для онов суми замовлення
create or replace function update_order_total_func()
returns trigger as $$
declare
    v_order_id int;
begin
    -- перевір на видал чи дода/онов
    if tg_op = 'DELETE' then
        v_order_id = old.order_id;
    else
        v_order_id = new.order_id;
    end if;

    -- онов суми замов через функцію
    update orders
    set total_amount = calculate_order_total(v_order_id)
    where order_id = v_order_id;

    return null;
end;
$$ language plpgsql;
