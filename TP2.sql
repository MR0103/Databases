--	TRABAJO PRÁCTICO No. 2
--	Programación Plpgsql - Funciones

--  a. Crear una función que permita eliminar espacios en blanco innecesarios (trim) de una 
--  columna de una tabla. Los nombres de columna y tabla deben ser pasados como 
--  parámetros y la función deberá devolver como resultado la cantidad de filas afectadas.
create or replace function delete_trim(pv_table_name varchar, pv_column_name varchar)
returns int as 
$$
declare contador integer := 0;
begin 
	execute 'update ' || pv_table_name || ' set ' || pv_column_name || ' = trim(' || pv_column_name || ') where not ' || pv_column_name || ' = trim(' || pv_column_name || ');';
	get diagnostics contador := ROW_COUNT;
	return contador;
end
$$
language plpgsql;

select * from delete_trim('products','productname');

--  b. Programar una función que reciba como parámetro un orderid y devuelva una cadena 
--  de caracteres (resumen) con el id, nombre, precio unitario y cantidad de todos los 
--  productos incluidos en la orden en cuestión.
--  Ejemplo: orderid = 11077, debería devolver
--  3-Aniseed Syrup-10.00-4, 60-Camembert Pierrot-34.00-2, 2-Chang-19.00-24,…

create or replace function get_order_details(pv_orderid int)
returns text
as $$
declare
    order_info text := '';
    product_row RECORD;
begin
    for product_row in (
        select p.productid, p.productname, od.unitprice, od.quantity
        from orderdetails od inner join products p using(productid)
        where od.orderid = pv_orderid
    ) loop
        order_info := order_info || product_row.productid || ' - ' || product_row.productname||
                      ' - ' || product_row.unitprice || ' - ' || product_row.quantity || ',';
    end loop;
    return order_info;
end;
$$ language plpgsql;

select * from get_order_details('11077');

--  c. Crear una función que muestre por cada detalle de orden, el nombre del cliente, la 
--  fecha, la identificación de cada artículo (Id y Nombre), cantidad, importe unitario y 
--  subtotal de cada ítem para un intervalo de tiempo dado por parámetros. 

create or replace function get_order_details_in_time_interval(
    pv_start_date date,
    pv_end_date date
)
returns table (
    companyname varchar(40),
    orderdate date,
    productid int,
    productname varchar(40),
    quantity int,
    unitprice numeric(10,2),
    subtotal numeric(10,2)
)
as 
$$
begin
    return query
    select
        c.companyname,
        o.orderdate,
        od.productid,
        p.productname,
        od.quantity,
        od.unitprice,
        (od.quantity * od.unitprice - od.discount) as subtotal
    from 
    	customers c
    	inner join orders o  using(customerid) 
    	inner join orderdetails od using(orderid) 
    	inner join products p using(productid)
    where 
        o.orderdate between pv_start_date and pv_end_date;
end;
$$
language plpgsql;

select * from get_order_details_in_time_interval('1996-07-04','1996-08-04');


--  d. Crear una función para el devolver el total de una orden dada por parámetro.
create or replace function subtotal_to_order(pv_orderid int)
returns money as
$$
declare 
	subtotal money;
begin
	subtotal = (
		select coalesce(sum(od.unitprice * od.quantity - od.discount),0)
		from orderdetails od
		where od.orderid = pv_orderid
	);
	return subtotal;
end;
$$
language plpgsql;

select * from subtotal_to_order('10249');

--  e. Crear una función donde se muestren todos los atributos de cada Orden junto a Id y 
--  Nombre del Cliente y el Empleado que la confeccionó. Mostrar el total utilizando la 
--  función del punto anterior.

create or replace function orders_details()
returns table (
	orderid int4,
	customerid varchar(5),
	employeeid int4,
	orderdate date,
	requireddate date,
	shippeddate date,
	shipvia int4,
	freight numeric(10, 2),
	shipname varchar(40),
	shipaddress varchar(60),
	shipcity varchar(15),
	shipregion varchar(15),
	shippostalcode varchar(10),
	shipcountry varchar(15),
 	companyname varchar(40),
	lastname varchar,
	firstname varchar,
	subtotal money
)
as
$$
begin
    return query
	select 
		o.*,
		c.companyname,
		e.lastname, 
		e.firstname, 
		(select * from subtotal_to_order(o.orderid))
	from 
		customers c 
		right join orders o using(customerid) 
		inner join orderdetails od using(orderid) 
		left join employees e using(employeeid)
	group by o.orderid, e.employeeid, c.customerid
	;
end;
$$
language plpgsql;

select * from orders_details();
select orderid from orders limit 1;

--  f. Crear una función que muestre, por cada mes del año ingresado por parámetro, la 
--  cantidad de órdenes generada, junto a la cantidad de órdenes acumuladas hasta ese 
--  mes (inclusive).
create or replace function details_by_year(pi_anio varchar(4))
returns table (
    mes text,
    ord_gen bigint, -- tipo que devuelve count()
    ord_ac bigint
) as $$
begin
    ord_ac := 0;
    for mes, ord_gen in
        select
            to_char(orderdate, 'tmmonth'),
            count(orderid)
        from orders
        where to_char(orderdate, 'yyyy') = pi_anio
        group by
            date_part('month', orderdate),
            to_char(orderdate, 'tmmonth')
        order by date_part('month', orderdate)
    loop
        ord_ac := ord_ac + ord_gen;
        return next;
    end loop;
end;
$$ language plpgsql;

select * from details_by_year('1997');



--  g. Crear una función que permita generar las órdenes de compra necesarias 
--  para todos los productos que se encuentran por debajo del nivel de stock, 
--  para esto deberá crear una tabla de órdenes de compra y su correspondiente 
--  tabla de detalles.

-- reorderlevel minimo
-- unitsinstock stock actual
-- unitsonorder stock que debe haber disponible

drop table purchases;
create table purchases(
	purchaseid serial primary key,
	purchasedate date,
	supplierid int4 not null,foreign key (supplierid) references suppliers
);
drop table purchasedetails;
create table purchasedetails (
	purchaseid integer not null,foreign key (purchaseid) references purchases,
	productid int4 not null,foreign key (productid) references products,  
	quantity int4,
	primary key(purchaseid,productid)
);

create or replace function stock_control()
returns void as 
$$
declare 
	li_current_supplierd int4 := '000';
 	li_purchaseid integer;
 	lr_prod RECORD;
begin 
	for lr_prod in (
		select 
			productid,
			unitsonorder - unitsinstock as units,
			supplierid 
		from 
			products
			inner join suppliers using(supplierid) 
		where 
			unitsinstock < reorderlevel 
			and unitsonorder - unitsinstock > '0'
		order by supplierid
		)
	loop
		if lr_prod.supplierid != li_current_supplierd then
			 insert into purchases values (DEFAULT,current_date,lr_prod.supplierid)
			 returning(purchaseid) into li_purchaseid;
		end if;
		insert into purchasedetails values (li_purchaseid , lr_prod.productid ,lr_prod.units );
    end loop;
end;
$$
language plpgsql;

select * from stock_control();
select * 
from 
	purchases
	inner join purchasedetails using(purchaseid)
;
--  h. Crear una función que calcule y despliegue por cada país destino de ordenes 
--  (orders.shipcountry) y por un rango de fechas ingresado por parámetros la cantidad 
--  de productos diferentes que se vendieron y la cantidad de clientes diferentes. Ejemplo 
--  de salida:
--  |shipcountry |productos | clientes
--  |Argentina   |20        | 5
--  |Austria     |45        | 12
--  |Belgium     |9         | 2
--  |… … …

create or replace function details_by_country(
    pv_start_date date,
    pv_end_date date
)
returns table (
    shipcountry_ varchar(15),
    different_products integer,
    different_customers integer
)
as $$
declare
    current_country varchar(15);
begin
    for current_country in (
    	select distinct shipcountry from orders
    	where orderdate between pv_start_date and pv_end_date
    	order by 1
    	) loop
        select
            o.shipcountry,
            count(distinct od.productid), 
            count(distinct o.customerid)
        into
            shipcountry_,
            different_products,
            different_customers
        from
            orders o 
            inner join orderdetails od using(orderid)
        where
            trim(o.shipcountry) = trim(current_country)
            and o.orderdate between pv_start_date and pv_end_date
        group by o.shipcountry;
        return next;
    end loop;
end;
$$ language plpgsql;

select * from details_by_country('1996-07-04','1996-08-04');

--  i. Inventar una única función que combine RETURN QUERY, recorrido de resultados de 
--  SELECT y RETURN NEXT. Indicar, además del código, qué se espera que devuelva la 
--  función inventada.

create or replace function get_orders() 
returns table (
    pi_orderid int,
    lv_customerid varchar,
    li_employeeid int,
    ld_orderdate date
) as $$
declare
    lr_order RECORD;
begin
    for lr_order in
        select 
        	orderid, 
        	customerid, 
        	employeeid, 
        	orderdate 
        from 
        	orders 
        where 
        	customerid ilike 'VINET'
    loop
        pi_orderid := lr_order.orderid;
        lv_customerid := lr_order.customerid;
        li_employeeid := lr_order.employeeid;
        ld_orderdate := lr_order.orderdate;
        return next;
    end loop;
end; $$
language 'plpgsql';

SELECT * from get_orders();

-- Esto devolverá un conjunto de resultados con
-- una fila para cada pedido del cliente 'VINET',
-- con las columnas definidas en la declaración.

