function hasLeadingUnderscore(text) {
  return text && text[0] === '_'
}

class Base {
  constructor(reporter, config, source, fileName) {
    this.reporter = reporter;
    this.ignored = this.constructor.global;
    this.ruleId = this.constructor.ruleId;
    if (this.ruleId === undefined) {
      throw Error('missing ruleId static property');
    }
  }

  error(node, message) {
    if (!this.ignored) {
      this.reporter.error(node, this.ruleId, message);
    }
  }
}

module.exports = [
  class extends Base {
    static ruleId = 'private-variables';

    VariableDeclaration(node) {
      const constantOrImmutable = node.isDeclaredConst || node.isImmutable;
      if (node.isStateVar && !constantOrImmutable && node.visibility !== 'private') {
        this.error(node, 'State variables must be private');
      }
    }
  },

  class extends Base {
    static ruleId = 'leading-underscore';

    ContractDefinition(node) {
      if (node.kind === 'library') {
        this.inLibrary = true
      }
    }

    'ContractDefinition:exit'() {
      this.inLibrary = false
    }

    StateVariableDeclaration() {
      this.inStateVariableDeclaration = true
    }

    'StateVariableDeclaration:exit'() {
      this.inStateVariableDeclaration = false
    }

    VariableDeclaration(node) {
      if (!this.inLibrary) {
        if (!this.inStateVariableDeclaration) {
            this.validateName(node, false, 'variable')
          return
        }
        const isPrivate = node.visibility === 'private'
        const isInternal = node.visibility === 'internal' || node.visibility === 'default'
        const isConstant = node.isDeclaredConst
        const shouldHaveLeadingUnderscore = (isPrivate || isInternal) && !isConstant
        this.validateName(node, shouldHaveLeadingUnderscore, 'variable')
      }

    }

    FunctionDefinition(node) {
      if (!this.inLibrary) {
        if (!node.name) {
          return
        }
  
        const isPrivate = node.visibility === 'private'
        const isInternal = node.visibility === 'internal' || node.visibility === 'default'
        const isConstant = node.isDeclaredConst
        const shouldHaveLeadingUnderscore = (isPrivate || isInternal) && !isConstant
        this.validateName(node, shouldHaveLeadingUnderscore, 'function')
      }
    }

    validateName(node, shouldHaveLeadingUnderscore, type) {
      if (node.name === null) {
        return
      }
  
      if (hasLeadingUnderscore(node.name) !== shouldHaveLeadingUnderscore) {
        this._error(node, node.name, shouldHaveLeadingUnderscore, type)
      }
    }

    _error(node, name, shouldHaveLeadingUnderscore) {
      this.error(node, `'${name}' ${shouldHaveLeadingUnderscore ? 'should' : 'should not'} start with _`)
    }
  },

];