USE [PRP]
GO

/****** Object:  StoredProcedure [dbo].[qrySoPRPDealerPackage]    Script Date: 10/07/2019 10:21:51 ******/
SET ANSI_NULLS OFF
GO

SET QUOTED_IDENTIFIER OFF
GO

-- exec qrySoPRPDealerPackage '.05', '2014', 1015, 'HE-'     /* MJM/PRP 3/13/15 */

CREATE PROCEDURE [dbo].[qrySoPRPDealerPackage] 

@PercentageOfSales as pdec,
@PreviousSalesYear varchar(4),
@TargetAmt pdec,
@ProductlinePrefix varchar(3)


AS


create table #ProductLineSales(
Itemid pItemID,
ItemDescr varchar(35) default '',
Qty pdec default(0))

--initial build of the data

insert #ProductLineSales(ItemId, ItemDescr)
select distinct a.ItemId as ItemId, i.descr from tblInItemAlias a inner join tblInItem i on a.ItemId = i.itemid 
WHERE LEFT(a.AliasId, CHARINDEX('-', a.AliasId)) = @ProductlinePrefix 
and LEFT(a.ItemId, CHARINDEX('-', a.ItemId)) = 'P-' and i.salescat <> 'ST'
union
select itemid, descr from tblInItem
where LEFT(ItemId, CHARINDEX('-', ItemId)) = @ProductlinePrefix and salescat <> 'ST'
order by ItemId

-- % of total quantity sold
update p set Qty =  --round(s.QtySold *  @PercentageOfSales, 0, 1)
(Select CASE WHEN (ROUND(s.QtySold , 0, 1) < 10) THEN
ROUND(s.QtySold / 2, 0, 1)
Else
ROUND(s.QtySold * @PercentageOfSales, 0, 1)
END)
from #ProductLineSales p inner join
(SELECT ItemId, SUM(QtySold)-SUM(QtyRetSold) as QtySold
FROM   tblInHistSum WHERE SumYear = @PreviousSalesYear and LocID='01'
GROUP BY ItemID) s
on p.itemid=s.itemid


-- create a table to process the items totaling the package target price
create table #results(
Itemid pItemID,
ItemDescr varchar(35) default '',
Qty pdec default(0),
WhsPrice pdec default(0),
ExtWhsPrice pdec default(0))

--declare @TargetAmt dec
--set @TargetAmt = 10000.00
declare @Sum pdec
set @Sum = 0
declare @ItemId pItemId
declare @ItemDescr varchar(30)
declare @message varchar(80)
declare @Qty pdec

DECLARE itemid_cursor CURSOR
FOR SELECT itemid, itemdescr, Qty FROM #ProductLineSales where Qty <> 0
order by Qty Desc
OPEN itemid_cursor

WHILE @Sum < @TargetAmt

BEGIN


FETCH NEXT FROM itemid_cursor 
INTO @ItemId, @ItemDescr, @Qty
-- Build data

insert #results(ItemId, ItemDescr, Qty, WhsPrice)
select @ItemId, @ItemDescr, @Qty, lup.PriceBase - (lup.PriceBase * (Cast(i.PriceID as decimal)* .01)) as WhsPrice
from tblInItem i inner join tblInItemLocUomPrice lup on i.itemid = lup.itemid
where @ItemId = i.ItemId

-- update the extended wholesale price 
update r set r.ExtWhsPrice = r.Qty * r.WhsPrice
from #results r

-- sum of extended
Set @Sum = (select SUM(ExtWhsPrice) from #results) 

	
END 
CLOSE itemid_cursor
DEALLOCATE itemid_cursor


if @Sum > @TargetAmt -- remove (lessor selling item)
begin

	while @Sum > @TargetAmt
	begin
	
	SELECT  * into #tmp FROM #results
	ORDER BY Qty ASC
	-- delete the top item (lowest sales)
	delete #results where itemid in (select top 1 itemid from #tmp)
	
	--UPDATE r SET r.Qty = r.Qty - 1
	--from #results r inner join #tmp t on r.itemid = t.itemid
	 -- Subtract until near @TargetAmt
	--UPDATE r set r.ExtWhsPrice = r.Qty * r.WhsPrice
	--from #results r inner join #tmp t on r.itemid = t.itemid
	
	set @Sum = (select SUM(ExtWhsPrice) from #results)
	drop table #tmp
	end


end

select * from #results order by qty desc
GO

