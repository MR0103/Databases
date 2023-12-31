-- 1. Insertar en la tabla region la nueva Región: Noroeste Argentino con el ID nro 5.
insert to region values (5,'Noroeste Argentino');

select *
from region
where regionid = 5;


-- 2. Insertar en la tabla territories al menos 5 territorios de la nueva región utilizando la sintaxis 
-- multirow de insert.
insert into territories 
values ('4400','Salta',5),
		('4600','Jujuy',5), 
		('4000','Tucumán',5), 
		('4200','Santiago del Estero',5), 
		('4700','Catamarca',5)
;

select *
from territories
where regionid = 5
order by territoryid 
;

-- 3. Crear una nueva tabla tmpterritories con los siguientes atributos:
-- territoryid
-- territorydescription
-- regionid
-- regiondescription

create table tmpterritories ( 
	territoryid varchar(20), foreign key (territoryid)references territories,
	territorydescription varchar(50) not null,
	regionid int4, foreign key (regionid) references region,
	regiondescription varchar(50) not null
);

-- 4. Mediante la sintáxis INSERT .. SELECT llenar la tabla del punto 3 combinando información de las 
-- tablas región y territories.

insert into tmpterritories
select territoryid, territorydescription, regionid, regiondescription
from territories inner join region using(regionid)
returning *
;

-- 5. Agregar dos columnas, a la tabla customers, donde se almacene, en forma redundante:
-- ordersquantity: con la cantidad de órdenes del cliente en cuestión
-- ordersamount : el importe total de las órdenes realizadas

alter table customers add column ordersquantity int;
alter table customers add column ordersamount int;

-- a. Mediante sentencia UPDATE...FROM actualizar las columnas agregadas

--Dos modificaciones, dos operaciones
update customers as c1
set ordersquantity = auxiliar.cantidad
from (select c.customerid as cus, count(od.orderid) as cantidad
		from customers c left join orders od using(customerid)
		group by c.customerid
	)as auxiliar
where c1.customerid = auxiliar.cus
;

update customers as c1
set ordersamount = auxiliar.Importes_Acumulados
from (select c.customerid as cus, coalesce(sum((od.unitprice * od.quantity) - od.discount),0) as Importes_Acumulados
		from customers c left join orders o using(customerid) left join orderdetails od using(orderid)
		group by c.customerid
	)as auxiliar
where c1.customerid = auxiliar.cus
returning *
;

-- Dos modificaciones una actualizacion
update customers as c1
set ordersquantity = auxiliar.cantidad , ordersamount = auxiliar.Importes_Acumulados
from (  select c.customerid as cus,
			   count(o.orderid) as cantidad, 
			   coalesce(sum((od.unitprice * od.quantity) - od.discount),0) as Importes_Acumulados
		from customers c left join orders o using(customerid) left join orderdetails od using(orderid)
		where c.customerid ilike 'QUICK'
		group by c.customerid
	)as auxiliar
where c1.customerid = auxiliar.cus
;
--MAL count cuenta todas las tuplas que coincidan en orderdetails


select customerid , ordersquantity , ordersamount 
from customers
where customerid ilike 'QUICK'
order by ordersamount desc
;

--Res Entregada
update customers c set
    ordersquantity = a.cantidad,
    ordersamount = b.monto
from (
    select
        count(o.orderid) as cantidad,
        ca.customerid
    from customers ca left join orders o using(customerid)
    group by ca.customerid
) a, (
    select
        coalesce(sum( (od.unitprice * od.quantity) - od.discount), 0) as monto,
        cb.customerid
    from customers cb
        left join orders o using(customerid)
        left join orderdetails od using(orderid)
    group by cb.customerid
) b
where
    c.customerid = a.customerid
    and c.customerid = b.customerid;
   
--Res Correcta
update customers c set
    ordersquantity = a.cantidad,
    ordersamount = b.monto
from (
    select
        count(orderid) as cantidad,
    from orders
    group by customerid
) a, (
    select
        coalesce(sum( (od.unitprice * od.quantity) - od.discount), 0) as monto,
        o.customerid
    from orders o 
        inner join orderdetails od using(orderid)
    group by o.customerid
) b
where
    c.customerid = a.customerid
    and c.customerid = b.customerid;
  --REVISAR

-- b. Mediante sentencia UPDATE y sunconsulta actualizar las columnas agregadas
update customers as c1
set ordersamount = (
	select count(o.customerid)
	from orders o
	where o.customerid = c1.customerid 
	group by o.orderid 
	)
where c1.ordersamount is null 
;

update customers as c1
set ordersamount = (
	select sum((od.unitprice * od.quantity) - od.discount)
	from orders o inner join orderdetails od using(orderid)
	where o.customerid = c1.customerid 
	group by o.orderid 
	)
where c1.ordersamount is null 
;

update customers as c1
set ordersquantity  = (
	select count(o.customerid)
	from orders o
	where o.customerid = c1.customerid 
	),
	ordersamount = (
	select sum((od.unitprice * od.quantity) - od.discount)
	from orders o left join orderdetails od using(orderid)
	where o.customerid = c1.customerid 
	) 
;

-- 6. Desarrollar las sentencias necesarias que permitan eliminar todo el historial 
-- de órdenes de un 
-- cliente cuyo dato conocido es companyname, utilizando DELETE…USING-- 

delete from orders as o
using (
	select c.customerid as customer
	from customers as c
	where c.companyname ilike 'companyname'
	) as c1
where c1.customer = o.customerid
;
 

