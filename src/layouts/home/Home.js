import React, { Component } from 'react'
import { AccountData, ContractData, ContractForm } from 'drizzle-react-components'

import OwnerData from '../../components/OwnerData'
// import logo from '../../logo.png'

class Home extends Component {
  render() {
    return (
      <main className="container">
        <div className="pure-g">
          <div className="pure-u-1-1 header">
            {/* <img src={logo} alt="drizzle-logo" /> */}
            <h1>The Graph Protocol</h1>
            <p>Truffle Testing Dashboard</p>

            <br/><br/>
          </div>

          <div className="pure-u-1-1">
            <h3>MultiSigWallet:</h3> <ContractData contract="MultiSigWallet" method="contractAddress" />
            <br /><br />
          </div>

          {/* <div className="pure-u-1-1">
            <h2>Owner / Sole Governor</h2>
            <AccountData accountIndex="0" units="ether" precision="3" />

            <br/><br/>
          </div> */}

          <div className="pure-u-1-1">
            <h2>Multisig Owners</h2>
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="0" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="1" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="2" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="3" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="4" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="5" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="6" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="7" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="8" /><br />
            <ContractData contract="MultiSigWallet" method="owners" methodArgs="9" /><br />
            {/* <ContractData contract="MultiSigWallet" method="owners" methodArgs="10" /><br /> */}
            {/* <ContractData contract="MultiSigWallet" method="owners" methodArgs="11" /><br /> */}
            {/* <OwnerData accountIndex="0" units="ether" precision="3" /> */}
            <br/><br/>
          </div>

          <div className="pure-u-1-1">
            <h2>Ubgradeable Contracts</h2>
            <p>This shows the deployed Contracts and their owners. They will initially be owned by the address which deployed them. They can then be transferred to the multisig address after deployment. Look for the web control below.</p>
            {/* <ContractData contract="Governance" method="allUpgradableContracts" /> */}

            <br /><br />
            <strong>Governance:</strong> 
            <br />
            <strong>owner:</strong> <ContractData contract="Governance" method="owner" />
            <br /><br />

            <br /><br />
            <strong>GraphToken:</strong> <ContractData contract="Governance" method="upgradableContracts" methodArgs="0" />
            <br />
            <strong>owner:</strong> <ContractData contract="GraphToken" method="owner" />
            <br /><br />

            <br /><br />
            <strong>Staking:</strong> <ContractData contract="Governance" method="upgradableContracts" methodArgs="1" />
            <br />
            <strong>owner:</strong> <ContractData contract="Staking" method="owner" />
            <br /><br />

            <br /><br />
            <strong>GNS:</strong> <ContractData contract="Governance" method="upgradableContracts" methodArgs="2" />
            <br />
            <strong>owner:</strong> <ContractData contract="GNS" method="owner" />
            <br /><br />
            
            <br /><br />
            <strong>Registry:</strong> <ContractData contract="Governance" method="upgradableContracts" methodArgs="3" />
            <br />
            <strong>owner:</strong> <ContractData contract="Registry" method="owner" />
            <br /><br />            
            
            <br /><br />
            <strong>RewardManager:</strong> <ContractData contract="Governance" method="upgradableContracts" methodArgs="4" />
            <br />
            <strong>owner:</strong> <ContractData contract="RewardManager" method="owner" />
            <br /><br />

            <hr />

            <br /><br />
            <strong>Governance.transferOwnershipOfAllContracts:</strong><br />
            <ContractForm contract="Governance" method="transferOwnershipOfAllContracts" />
            <br /><br />

            <br /><br />
            <strong>MultiSigWallet.submitTransaction > Governance.acceptOwnershipOfAllContracts:</strong><br />
            <ContractForm contract="MultiSigWallet" method="submitTransaction" />
            <br /><br />

            <br/><br/>
          </div>

          {/* <div className="pure-u-1-1">
            <h2>Initiate Transfer Ownership of All Contracts</h2>
            <p>This Transfers Ownership of all the Upgradeable Contracts.</p>
            <p><strong>Stored Value</strong>: <ContractData contract="SimpleStorage" method="storedData" /></p>
            <ContractForm contract="SimpleStorage" method="set" />

            <br/><br/>
          </div>

          <div className="pure-u-1-1">
            <h2>Accept Transfer Ownership of All Contracts</h2>
            <p>This Accepts and completes the Transfer of Ownership of all the Upgradeable Contracts.</p>
            <p><strong>Stored Value</strong>: <ContractData contract="SimpleStorage" method="storedData" /></p>
            <ContractForm contract="SimpleStorage" method="set" />

            <br/><br/>
          </div> */}



          {/* <div className="pure-u-1-1">
            <h2>TutorialToken</h2>
            <p>Here we have a form with custom, friendly labels. Also note the token symbol will not display a loading indicator. We've suppressed it with the <code>hideIndicator</code> prop because we know this variable is constant.</p>
            <p><strong>Total Supply</strong>: <ContractData contract="TutorialToken" method="totalSupply" methodArgs={[{from: this.props.accounts[0]}]} /> <ContractData contract="TutorialToken" method="symbol" hideIndicator /></p>
            <p><strong>My Balance</strong>: <ContractData contract="TutorialToken" method="balanceOf" methodArgs={[this.props.accounts[0]]} /></p>
            <h3>Send Tokens</h3>
            <ContractForm contract="TutorialToken" method="transfer" labels={['To Address', 'Amount to Send']} />

            <br/><br/>
          </div>

          <div className="pure-u-1-1">
            <h2>ComplexStorage</h2>
            <p>Finally this contract shows data types with additional considerations. Note in the code the strings below are converted from bytes to UTF-8 strings and the device data struct is iterated as a list.</p>
            <p><strong>String 1</strong>: <ContractData contract="ComplexStorage" method="string1" toUtf8 /></p>
            <p><strong>String 2</strong>: <ContractData contract="ComplexStorage" method="string2" toUtf8 /></p>
            <strong>Single Device Data</strong>: <ContractData contract="ComplexStorage" method="singleDD" />

            <br/><br/>
          </div> */}
        </div>
      </main>
    )
  }
}

export default Home
