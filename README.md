# Food Map

一个可持续扩展的美食地图。当前包含：

- 重庆
- 四川/成都

## 数据结构

地图入口是 `index.html`，数据在 `food-data.js`。

新增城市、地区或国家时：

1. 在 `destinations` 里加一个目的地。
2. 在 `items` 里加点位，`destination` 填目的地 `id`。
3. 如果是中国大陆坐标，可以直接填高德/Apple Maps 常见坐标，页面会自动转换到 OpenStreetMap 底图。

`category` 可用值：

- `snack`：小吃早餐
- `meal`：江湖家常
- `hotpot`：火锅串串
- `sweet`：甜品饮品
- `place`：片区景点

`confidence` 可用值：

- `high`：定位较准
- `medium`：多分店或需核对
- `low`：小摊、片区或临时摊位
