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

  error(node, message, fix) {
    if (!this.ignored) {
      this.reporter.error(node, this.ruleId, message, fix);
    }
  }
}

module.exports = [
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

        this.validateName(node, 'variable')
      }

    }

    FunctionDefinition(node) {
      if (!this.inLibrary) {
        if (!node.name) {
          return
        }

        this.validateName(node, 'function')
      }
    }


    validateName(node, type) {
      const isPrivate = node.visibility === 'private'
      const isInternal = node.visibility === 'internal' || node.visibility === 'default'
      const isConstant = node.isDeclaredConst
      const shouldHaveLeadingUnderscore = (isPrivate || isInternal) && !isConstant

      if (node.name === null) {
        return
      }
  
      if (hasLeadingUnderscore(node.name) !== shouldHaveLeadingUnderscore) {
        this._error(node, node.name, shouldHaveLeadingUnderscore, type)
      }
    }

    fixStatement(node, shouldHaveLeadingUnderscore, type) {
      let range
  
      if (type === 'function') {
        range = node.range
        range[0] += 8
      } else {
        range = node.identifier.range
        range[0] -= 1
      }
  
      return (fixer) =>
        shouldHaveLeadingUnderscore
          ? fixer.insertTextBeforeRange(range, ' _')
          : fixer.removeRange([range[0] + 1, range[0] + 1])
    }

    _error(node, name, shouldHaveLeadingUnderscore, type) {
      this.error(
        node,
        `'${name}' ${shouldHaveLeadingUnderscore ? 'should' : 'should not'} start with _`,
        this.fixStatement(node, shouldHaveLeadingUnderscore, type)
      )
    }
  },

];