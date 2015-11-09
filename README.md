# commvault-cookbook

Cookbook to install CommVault client. Create a customer install for the features that are required.

http://documentation.commvault.com/commvault/v10/article?p=deployment/install/reduced_package/reduced_package.htm

## Supported Platforms

Windows

## Attributes

<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>['commvault']['bacon']</tt></td>
    <td>Boolean</td>
    <td>whether to include bacon</td>
    <td><tt>true</tt></td>
  </tr>
</table>

## Usage

### commvault::default

Include `commvault` in your node's `run_list`:

```json
{
  "run_list": [
    "recipe[commvault::default]"
  ]
}
```

## License and Authors

Author:: Taliesin Sisson (taliesins@yahoo.com)
